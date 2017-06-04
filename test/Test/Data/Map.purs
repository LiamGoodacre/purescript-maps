module Test.Data.Map where

import Prelude
import Control.Alt ((<|>))
import Control.Monad.Eff (Eff)
import Control.Monad.Eff.Console (log, CONSOLE)
import Control.Monad.Eff.Exception (EXCEPTION)
import Control.Monad.Eff.Random (RANDOM)
import Data.Foldable (foldl, for_, all)
import Data.Function (on)
import Data.List (List(Cons), groupBy, length, nubBy, singleton, sort, sortBy)
import Data.List.NonEmpty as NEL
import Data.Map as M
import Data.Maybe (Maybe(..), fromMaybe)
import Data.NonEmpty ((:|))
import Data.Tuple (Tuple(..), fst)
import Partial.Unsafe (unsafePartial)
import Test.QuickCheck ((<?>), (===), quickCheck, quickCheck')
import Test.QuickCheck.Gen (elements, oneOf)
import Test.QuickCheck.Arbitrary (class Arbitrary, arbitrary)

newtype TestMap k v = TestMap (M.Map k v)

instance arbTestMap :: (Eq k, Ord k, Arbitrary k, Arbitrary v) => Arbitrary (TestMap k v) where
  arbitrary = TestMap <<< (M.fromFoldable :: List (Tuple k v) -> M.Map k v) <$> arbitrary

data SmallKey = A | B | C | D | E | F | G | H | I | J
derive instance eqSmallKey :: Eq SmallKey
derive instance ordSmallKey :: Ord SmallKey

instance showSmallKey :: Show SmallKey where
  show A = "A"
  show B = "B"
  show C = "C"
  show D = "D"
  show E = "E"
  show F = "F"
  show G = "G"
  show H = "H"
  show I = "I"
  show J = "J"

instance arbSmallKey :: Arbitrary SmallKey where
  arbitrary = elements $ A :| [B, C, D, E, F, G, H, I, J]

data Instruction k v = Insert k v | Delete k

instance showInstruction :: (Show k, Show v) => Show (Instruction k v) where
  show (Insert k v) = "Insert (" <> show k <> ") (" <> show v <> ")"
  show (Delete k) = "Delete (" <> show k <> ")"

instance arbInstruction :: (Arbitrary k, Arbitrary v) => Arbitrary (Instruction k v) where
  arbitrary = oneOf $ (Insert <$> arbitrary <*> arbitrary) :| [Delete <$> arbitrary]

runInstructions :: forall k v. Ord k => List (Instruction k v) -> M.Map k v -> M.Map k v
runInstructions instrs t0 = foldl step t0 instrs
  where
  step tree (Insert k v) = M.insert k v tree
  step tree (Delete k) = M.delete k tree

smallKey :: SmallKey -> SmallKey
smallKey k = k

number :: Int -> Int
number n = n

smallKeyToNumberMap :: M.Map SmallKey Int -> M.Map SmallKey Int
smallKeyToNumberMap m = m

mapTests :: forall eff. Eff (console :: CONSOLE, random :: RANDOM, exception :: EXCEPTION | eff) Unit
mapTests = do

  -- Data.Map

  log "Test inserting into empty tree"
  quickCheck $ \k v -> M.lookup (smallKey k) (M.insert k v M.empty) == Just (number v)
    <?> ("k: " <> show k <> ", v: " <> show v)

  log "Test inserting two values with same key"
  quickCheck $ \k v1 v2 ->
    M.lookup (smallKey k) (M.insert k v2 (M.insert k v1 M.empty)) == Just (number v2)

  log "Test delete after inserting"
  quickCheck $ \k v -> M.isEmpty (M.delete (smallKey k) (M.insert k (number v) M.empty))
    <?> ("k: " <> show k <> ", v: " <> show v)

  log "Test pop after inserting"
  quickCheck $ \k v -> M.pop (smallKey k) (M.insert k (number v) M.empty) == Just (Tuple v M.empty)
    <?> ("k: " <> show k <> ", v: " <> show v)

  log "Pop non-existent key"
  quickCheck $ \k1 k2 v -> k1 == k2 || M.pop (smallKey k2) (M.insert k1 (number v) M.empty) == Nothing
    <?> ("k1: " <> show k1 <> ", k2: " <> show k2 <> ", v: " <> show v)

  log "Insert two, lookup first"
  quickCheck $ \k1 v1 k2 v2 -> k1 == k2 || M.lookup k1 (M.insert (smallKey k2) (number v2) (M.insert (smallKey k1) (number v1) M.empty)) == Just v1
    <?> ("k1: " <> show k1 <> ", v1: " <> show v1 <> ", k2: " <> show k2 <> ", v2: " <> show v2)

  log "Insert two, lookup second"
  quickCheck $ \k1 v1 k2 v2 -> M.lookup k2 (M.insert (smallKey k2) (number v2) (M.insert (smallKey k1) (number v1) M.empty)) == Just v2
    <?> ("k1: " <> show k1 <> ", v1: " <> show v1 <> ", k2: " <> show k2 <> ", v2: " <> show v2)

  log "Insert two, delete one"
  quickCheck $ \k1 v1 k2 v2 -> k1 == k2 || M.lookup k2 (M.delete k1 (M.insert (smallKey k2) (number v2) (M.insert (smallKey k1) (number v1) M.empty))) == Just v2
    <?> ("k1: " <> show k1 <> ", v1: " <> show v1 <> ", k2: " <> show k2 <> ", v2: " <> show v2)

  log "Check balance property"
  quickCheck' 1000 $ \instrs ->
    let
      tree :: M.Map SmallKey Int
      tree = runInstructions instrs M.empty
    in M.checkValid tree <?> ("Map not balanced:\n  " <> show tree <> "\nGenerated by:\n  " <> show instrs)

  log "Lookup from empty"
  quickCheck $ \k -> M.lookup k (M.empty :: M.Map SmallKey Int) == Nothing

  log "Lookup from singleton"
  quickCheck $ \k v -> M.lookup (k :: SmallKey) (M.singleton k (v :: Int)) == Just v

  log "Random lookup"
  quickCheck' 1000 $ \instrs k v ->
    let
      tree :: M.Map SmallKey Int
      tree = M.insert k v (runInstructions instrs M.empty)
    in M.lookup k tree == Just v <?> ("instrs:\n  " <> show instrs <> "\nk:\n  " <> show k <> "\nv:\n  " <> show v)

  log "Singleton to list"
  quickCheck $ \k v -> M.toUnfoldable (M.singleton k v :: M.Map SmallKey Int) == singleton (Tuple k v)

  log "fromFoldable [] = empty"
  quickCheck (M.fromFoldable [] == (M.empty :: M.Map Unit Unit)
    <?> "was not empty")

  log "fromFoldable & key collision"
  do
    let nums = M.fromFoldable [Tuple 0 "zero", Tuple 1 "what", Tuple 1 "one"]
    quickCheck (M.lookup 0 nums == Just "zero" <?> "invalid lookup - 0")
    quickCheck (M.lookup 1 nums == Just "one"  <?> "invalid lookup - 1")
    quickCheck (M.lookup 2 nums == Nothing     <?> "invalid lookup - 2")

  log "fromFoldableWith const [] = empty"
  quickCheck (M.fromFoldableWith const [] == (M.empty :: M.Map Unit Unit)
    <?> "was not empty")

  log "fromFoldableWith (+) & key collision"
  do
    let nums = M.fromFoldableWith (+) [Tuple 0 1, Tuple 1 1, Tuple 1 1]
    quickCheck (M.lookup 0 nums == Just 1  <?> "invalid lookup - 0")
    quickCheck (M.lookup 1 nums == Just 2  <?> "invalid lookup - 1")
    quickCheck (M.lookup 2 nums == Nothing <?> "invalid lookup - 2")

  log "sort . toUnfoldable . fromFoldable = sort (on lists without key-duplicates)"
  quickCheck $ \(list :: List (Tuple SmallKey Int)) ->
    let nubbedList = nubBy ((==) `on` fst) list
        f x = M.toUnfoldable (M.fromFoldable x)
    in sort (f nubbedList) == sort nubbedList <?> show nubbedList

  log "fromFoldable . toUnfoldable = id"
  quickCheck $ \(TestMap (m :: M.Map SmallKey Int)) ->
    let f m' = M.fromFoldable (M.toUnfoldable m' :: List (Tuple SmallKey Int))
    in f m == m <?> show m

  log "fromFoldableWith const = fromFoldable"
  quickCheck $ \arr ->
    M.fromFoldableWith const arr ==
    M.fromFoldable (arr :: List (Tuple SmallKey Int)) <?> show arr

  log "fromFoldableWith (<>) = fromFoldable . collapse with (<>) . group on fst"
  quickCheck $ \arr ->
    let combine (Tuple s a) (Tuple t b) = (Tuple s $ b <> a)
        foldl1 g = unsafePartial \(Cons x xs) -> foldl g x xs
        f = M.fromFoldable <<< map (foldl1 combine <<< NEL.toList) <<<
            groupBy ((==) `on` fst) <<< sortBy (compare `on` fst) in
    M.fromFoldableWith (<>) arr === f (arr :: List (Tuple String String))

  log "toAscUnfoldable is sorted version of toUnfoldable"
  quickCheck $ \(TestMap m) ->
    let list = M.toUnfoldable (m :: M.Map SmallKey Int)
        ascList = M.toAscUnfoldable m
    in ascList === sortBy (compare `on` fst) list

  log "Lookup from union"
  quickCheck $ \(TestMap m1) (TestMap m2) k ->
    M.lookup (smallKey k) (M.union m1 m2) == (case M.lookup k m1 of
      Nothing -> M.lookup k m2
      Just v -> Just (number v)) <?> ("m1: " <> show m1 <> ", m2: " <> show m2 <> ", k: " <> show k <> ", v1: " <> show (M.lookup k m1) <> ", v2: " <> show (M.lookup k m2) <> ", union: " <> show (M.union m1 m2))

  log "Union is idempotent"
  quickCheck $ \(TestMap m1) (TestMap m2) -> (m1 `M.union` m2) == ((m1 `M.union` m2) `M.union` (m2 :: M.Map SmallKey Int))

  log "Union prefers left"
  quickCheck $ \(TestMap m1) (TestMap m2) k -> M.lookup k (M.union m1 (m2 :: M.Map SmallKey Int)) == (M.lookup k m1 <|> M.lookup k m2)

  log "unionWith"
  for_ [Tuple (+) 0, Tuple (*) 1] $ \(Tuple op ident) ->
    quickCheck $ \(TestMap m1) (TestMap m2) k ->
      let u = M.unionWith op m1 m2 :: M.Map SmallKey Int
      in case M.lookup k u of
           Nothing -> not (M.member k m1 || M.member k m2)
           Just v -> v == op (fromMaybe ident (M.lookup k m1)) (fromMaybe ident (M.lookup k m2))

  log "unionWith argument order"
  quickCheck $ \(TestMap m1) (TestMap m2) k ->
    let u   = M.unionWith (-) m1 m2 :: M.Map SmallKey Int
        in1 = M.member k m1
        v1  = M.lookup k m1
        in2 = M.member k m2
        v2  = M.lookup k m2
    in case M.lookup k u of
          Just v | in1 && in2 -> Just v == ((-) <$> v1 <*> v2)
          Just v | in1        -> Just v == v1
          Just v              -> Just v == v2
          Nothing             -> not (in1 || in2)

  log "size"
  quickCheck $ \xs ->
    let xs' = nubBy ((==) `on` fst) xs
    in  M.size (M.fromFoldable xs') == length (xs' :: List (Tuple SmallKey Int))

  log "lookupLE result is correct"
  quickCheck $ \k (TestMap m) -> case M.lookupLE k (smallKeyToNumberMap m) of
    Nothing -> all (_ > k) $ M.keys m
    Just { key: k1, value: v } -> let
      isCloserKey k2 = k1 < k2 && k2 < k
      isLTwhenEQexists = k1 < k && M.member k m
      in   k1 <= k
        && all (not <<< isCloserKey) (M.keys m)
        && not isLTwhenEQexists
        && M.lookup k1 m == Just v

  log "lookupGE result is correct"
  quickCheck $ \k (TestMap m) -> case M.lookupGE k (smallKeyToNumberMap m) of
    Nothing -> all (_ < k) $ M.keys m
    Just { key: k1, value: v } -> let
      isCloserKey k2 = k < k2 && k2 < k1
      isGTwhenEQexists = k < k1 && M.member k m
      in   k1 >= k
        && all (not <<< isCloserKey) (M.keys m)
        && not isGTwhenEQexists
        && M.lookup k1 m == Just v

  log "lookupLT result is correct"
  quickCheck $ \k (TestMap m) -> case M.lookupLT k (smallKeyToNumberMap m) of
    Nothing -> all (_ >= k) $ M.keys m
    Just { key: k1, value: v } -> let
      isCloserKey k2 = k1 < k2 && k2 < k
      in   k1 < k
        && all (not <<< isCloserKey) (M.keys m)
        && M.lookup k1 m == Just v

  log "lookupGT result is correct"
  quickCheck $ \k (TestMap m) -> case M.lookupGT k (smallKeyToNumberMap m) of
    Nothing -> all (_ <= k) $ M.keys m
    Just { key: k1, value: v } -> let
      isCloserKey k2 = k < k2 && k2 < k1
      in   k1 > k
        && all (not <<< isCloserKey) (M.keys m)
        && M.lookup k1 m == Just v

  log "findMin result is correct"
  quickCheck $ \(TestMap m) -> case M.findMin (smallKeyToNumberMap m) of
    Nothing -> M.isEmpty m
    Just { key: k, value: v } -> M.lookup k m == Just v && all (_ >= k) (M.keys m)

  log "findMax result is correct"
  quickCheck $ \(TestMap m) -> case M.findMax (smallKeyToNumberMap m) of
    Nothing -> M.isEmpty m
    Just { key: k, value: v } -> M.lookup k m == Just v && all (_ <= k) (M.keys m)

  log "mapWithKey is correct"
  quickCheck $ \(TestMap m :: TestMap String Int) -> let
    f k v = k <> show v
    resultViaMapWithKey = m # M.mapWithKey f
    toList = M.toUnfoldable :: forall k v. M.Map k v -> List (Tuple k v)
    resultViaLists = m # toList # map (\(Tuple k v) → Tuple k (f k v)) # M.fromFoldable
    in resultViaMapWithKey === resultViaLists

  log "onValues/frequencies"
  quickCheck $
    M.frequencies ["a", "b", "d", "c", "b", "d", "d"] === M.fromFoldable [Tuple "a" 1, Tuple "b" 2, Tuple "c" 1, Tuple "d" 3]
