{-# OPTIONS_GHC -Wno-deprecations #-}

module Streamly.Test.Unicode.Stream (main) where

import Data.Char (ord, chr)
import Data.Word (Word8)
import Test.QuickCheck
    ( Property
    , forAll
    , Gen
    , listOf
    , arbitraryASCIIChar
    , arbitraryUnicodeChar
    , arbitrary
    , expectFailure
    , vectorOf
    , choose
    )
import Test.QuickCheck.Monadic (run, monadicIO, assert)

import qualified Streamly.Data.Array as A
import qualified Streamly.Data.Stream as Stream
import qualified Streamly.Internal.Data.Array.Stream as AS
import qualified Streamly.Internal.Data.Stream as Stream
import qualified Streamly.Unicode.Stream as SS
import qualified Streamly.Internal.Unicode.Stream as IUS
import qualified Streamly.Internal.Unicode.Array as IUA
import qualified Test.Hspec as H

import Test.Hspec.QuickCheck

-- Coverage build takes too long with default number of tests
{-
maxTestCount :: Int
#ifdef DEVBUILD
maxTestCount = 100
#else
maxTestCount = 10
#endif
-}

-- Use quickcheck-unicode instead?
genUnicode :: Gen String
genUnicode = listOf arbitraryUnicodeChar

genWord8 :: Gen [Word8]
genWord8 = listOf arbitrary

propDecodeEncodeId' :: Property
propDecodeEncodeId' =
    forAll genUnicode $ \list ->
        monadicIO $ do
            let wrds = SS.encodeUtf8' $ Stream.fromList list
            chrs <- run $ Stream.toList $ SS.decodeUtf8' wrds
            assert (chrs == list)

-- XXX need to use invalid characters
propDecodeEncodeId :: Property
propDecodeEncodeId =
    forAll genUnicode $ \list ->
        monadicIO $ do
            let wrds = SS.encodeUtf8 $ Stream.fromList list
            chrs <- Stream.toList $ SS.decodeUtf8 wrds
            assert (chrs == list)

propDecodeEncodeIdArrays :: Property
propDecodeEncodeIdArrays =
    forAll genUnicode $ \list ->
        monadicIO $ do
            let wrds = Stream.chunksOf 8 $ SS.encodeUtf8' $ Stream.fromList list
            chrs <- Stream.toList $ IUS.decodeUtf8Chunks wrds
            assert (chrs == list)

unicodeTestData :: [Char]
unicodeTestData = "z\72150\83468;L$Wz| ?_i/J ."

latin1TestData :: [Char]
latin1TestData = "z\214\f;L$Wz| ?_i/J ."

propASCIIToLatin1 :: Property
propASCIIToLatin1 =
    forAll (choose (1, 1000)) $ \len ->
        forAll (vectorOf len arbitraryASCIIChar) $ \list ->
            monadicIO $ do
                let wrds = SS.decodeLatin1
                            $ SS.encodeLatin1
                            $ Stream.fromList list
                lst <- run $  Stream.toList wrds
                assert (list == lst)

propUnicodeToLatin1 :: Property
propUnicodeToLatin1 =
    monadicIO $ do
        let wrds =
                SS.decodeLatin1
                    $ SS.encodeLatin1
                    $ Stream.fromList unicodeTestData
        lst <- run $ Stream.toList wrds
        assert (latin1TestData == lst)

propUnicodeToLatin1' :: Property
propUnicodeToLatin1' =
    monadicIO $ do
        let wrds =
                SS.decodeLatin1
                    $ SS.encodeLatin1'
                    $ Stream.fromList unicodeTestData
        lst <- run $ Stream.toList wrds
        assert (latin1TestData == lst)

testLines :: Property
testLines =
    forAll genUnicode $ \list ->
        monadicIO $ do
            xs <- Stream.toList
                $ fmap A.toList
                $ IUA.lines
                $ Stream.fromList list
            assert (xs == lines list)

testLinesArray :: Property
testLinesArray =
    forAll genWord8 $ \list ->
        monadicIO $ do
            xs <- Stream.toList
                    $ fmap A.toList
                    $ AS.splitOnSuffix 10
                    $ Stream.fromPure (A.fromList list)
            assert (xs == map (map (fromIntegral . ord))
                              (lines (map (chr .  fromIntegral) list)))

testWords :: Property
testWords =
    forAll genUnicode $ \list ->
        monadicIO $ do
            xs <- Stream.toList
                $ Stream.map A.toList
                $ IUA.words
                $ Stream.fromList list
            assert (xs == words list)

testUnlines :: Property
testUnlines =
  forAll genUnicode $ \list ->
      monadicIO $ do
          xs <- Stream.toList
              $ IUA.unlines
              $ IUA.lines
              $ Stream.fromList list
          assert (xs == unlines (lines list))

testUnwords :: Property
testUnwords =
  forAll genUnicode $ \list ->
      monadicIO $ do
          xs <- run
              $ Stream.toList
              $ IUA.unwords
              $ IUA.words
              $ Stream.fromList list
          assert (xs == unwords (words list))

moduleName :: String
moduleName = "Unicode.Stream"

main :: IO ()
main = H.hspec
  $ H.parallel
  $ modifyMaxSuccess (const 1000)
  $ H.describe moduleName $ do
    H.describe "UTF8 - Encoding / Decoding" $ do
        prop "decodeUtf8' . encodeUtf8' == id" propDecodeEncodeId'
        prop "decodeUtf8 . encodeUtf8' == id" propDecodeEncodeId
        prop "decodeUtf8Arrays . encodeUtf8' == id"
                propDecodeEncodeIdArrays
        prop "Streamly.Data.String.lines == Prelude.lines" testLines
        prop "Arrays Streamly.Data.String.lines == Prelude.lines"
            testLinesArray
        prop "Streamly.Data.String.words == Prelude.words" testWords
        prop
            "Streamly.Data.String.unlines . Streamly.Data.String.lines == unlines . lines"
            testUnlines
        prop
            "Streamly.Data.String.unwords . Streamly.Data.String.words == unwords . words"
            testUnwords

    H.describe "Latin1 - Encoding / Decoding" $ do
        prop "ASCII to Latin1" propASCIIToLatin1
        prop "Unicode to Latin1" propUnicodeToLatin1
        prop "Unicode to Latin1'" $ expectFailure  propUnicodeToLatin1'
