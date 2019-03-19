module Duet.Interpreter where

import Duet.UVMHS

import Duet.Pretty ()
import Duet.Syntax
import Duet.RNF
import Duet.Quantity

-- libraries
import System.Random
import System.Random.MWC
import Data.Random.Normal

type Env = 𝕏 ⇰ Val
type DuetVector a = 𝐿 a

-- helpers

-- TODO: eventually add this to UVMHS
minElem ::  Ord b => (a → b) → 𝐿 a → a
minElem f Nil = error "minElem on empty list"
minElem f (x:&xs) = fold x (\ x₁ x₂ → case f x₁ < f x₂ of { True → x₁ ; False → x₂ }) xs

minElemPairs :: Ord b => 𝐿 (a ∧ b) → a ∧ b
minElemPairs = minElem snd

iota :: ℕ → 𝐿 ℕ
iota n = (single𝐿 0) ⧺ list (upTo (n-1))

head :: 𝐿 a → a
head (x:&xs) = x
head _ = error "head failed"

tail :: 𝐿 a → 𝐿 a
tail (x:&xs) = xs
tail _ = error "tail failed"

replicate :: ℕ → a → 𝐿 a
replicate len v = list $ build len v (\ x → x)

zipWith :: (a → b → c) → 𝐿 a → 𝐿 b → 𝐿 c
zipWith _ Nil _ = Nil
zipWith _ _ Nil = Nil
zipWith f (x:&xs) (y:&ys) = f x y :& zipWith f xs ys

take :: ℕ → 𝐿 𝔻 → 𝐿 𝔻
take 0 _ = Nil
take _ Nil= Nil
take n (x:&xs) = x :& take (n-1) xs

iterate :: (a → a) → a → [a]
iterate f a = a : iterate f (f a)

-- vector/matrix ops

norm_2 :: DuetVector 𝔻 → 𝔻
norm_2 = root ∘ sum ∘ map (\x → x×x)

cols :: ExMatrix a → ℕ
cols = nat ∘ unSℕ32 ∘ xcols ∘ ex2m

rows :: ExMatrix a → ℕ
rows = nat ∘ unSℕ32 ∘ xrows ∘ ex2m

tr :: ExMatrix 𝔻 → ExMatrix 𝔻
tr m = xbp $ xtranspose $ xvirt m

(===) :: ExMatrix a → ExMatrix a → ExMatrix a
(===) a b =
  let a₁ = toRows a
      b₁ = toRows b
      c = a₁ ⧺ b₁
  in fromRows c

ident :: ℕ → ExMatrix 𝔻
ident n = let m = [ [boolCheck $ i ≡ j | i <- list $ upTo n] | j <- list $ upTo n] in
  fromRows m

boolCheck :: 𝔹 → 𝔻
boolCheck True = 1.0
boolCheck False = 0.0

flatten :: ExMatrix 𝔻 → DuetVector 𝔻
flatten m = fold Nil (⧺) (toRows m)

(<>) :: ExMatrix 𝔻 → ExMatrix 𝔻 → ExMatrix 𝔻
(<>) a b =
  let a₁ = toRows a
      b₁ = toRows (tr b)
      c = [ [ sum $ zipWith (×) ar bc | bc <- b₁ ] | ar <- a₁ ]
  in fromRows c

scale :: 𝔻 → DuetVector 𝔻 → Model
scale r v = map (× r) v

mscale :: 𝔻 → ExMatrix 𝔻 → ExMatrix 𝔻
mscale r m = xbp $ xmap (× r) (xvirt m)

vector :: 𝐿 𝔻 → DuetVector 𝔻
vector x = x

fromList :: 𝐿 𝔻 → DuetVector 𝔻
fromList x = x

fromLists :: 𝐿 (𝐿 a) → ExMatrix a
fromLists = buildRows

fromRows = fromLists

-- creates a 1-column matrix from a vector
asColumn :: DuetVector a → ExMatrix a
asColumn vec = buildRows (map single𝐿 vec)

-- really build a matrix
buildRows :: 𝐿 (𝐿 a) → ExMatrix a
buildRows ls = xb𝐿 ls xbIdentity

xbIdentity ∷ Bᴍ m n a → Bᴍ m n a
xbIdentity x = x

-- extract rows in N
(?) :: ExMatrix 𝔻 → 𝐿 ℤ → ExMatrix 𝔻
(?) m ns = buildRows (iota (count ns)) (m ?? ns)

(??) :: ExMatrix 𝔻 → 𝐿 ℤ → 𝐿 (𝐿 𝔻)
(??) m (n:&ns) = (xlist2 (xrow (natΩ n) m)) ⧺ (m ?? ns)
(??) m Nil = Nil

toList :: DuetVector 𝔻 → 𝐿 𝔻
toList x = x

-- extracts the rows of a matrix as a list of vectors
toRows :: ExMatrix a → 𝐿 (𝐿 a)
toRows = xlist2 ∘ xvirt

toLists = toRows

-- size :: ExMatrix Val → (ℕ, ℕ)
-- size m = (xrows m, xcols m)

-- creates a 1-row matrix from a vector
asRow :: DuetVector a → ExMatrix a
asRow vec = fromLists $ list [vec]

(+++) :: (Plus a) => ExMatrix a → ExMatrix a → ExMatrix a
(+++) a b =
  let a₁ = toRows a
      b₁ = toRows b
      add = zipWith (zipWith (+))
      c = add a₁ b₁
  in fromRows c

(-/) :: (Minus a) => ExMatrix a → ExMatrix a → ExMatrix a
(-/) a b =
  let a₁ = toRows a
      b₁ = toRows b
      sub = zipWith (zipWith (-))
      c = sub a₁ b₁
  in fromRows c

urv :: Val → 𝔻
urv x = case x of
  RealV d → d
  _ → error $ "unpack real val failed" ⧺ pprender x

arsinh ∷ 𝔻 → 𝔻
arsinh x = log $ x + (root $ (x × x) + 1.0)

-- Nat, 1-row matrix (really a row), list of one row matrices, and so on
-- mostly because matrices are the only thing we can index
joinMatch₁ ∷ ℕ → ExMatrix Val → 𝐿 (ExMatrix Val) → ℕ → 𝐿 Val
joinMatch₁ n₁ row₁ Nil n₂ = Nil
joinMatch₁ n₁ row₁ (row₂:&rows₂) n₂ = case ((indexBᴍ 0 n₁ row₁) ≡ (indexBᴍ 0 n₂ row₂)) of
  True →  (flatten row₁) ⧺ (flatten row₂)
  False → joinMatch₁ n₁ row₁ rows₂ n₂

csvToMatrix ∷ 𝐿 (𝐿 𝕊) → Val
csvToMatrix sss =
  let csvList ∷ 𝐿 (𝐿 𝔻) = mapp read𝕊 sss
      m ∷ ExMatrix 𝔻 = fromLists csvList
  in MatrixV $ map RealV m

schemaToTypes :: MExp r → 𝐿 (Type r)
schemaToTypes me = case me of
  (ConsME τ me') → schemaToTypes₁ me
  _ → error "schemaToTypes expects a ConsME"

schemaToTypes₁ :: MExp r → 𝐿 (Type r)
schemaToTypes₁ me = case me of
  (ConsME τ me') → τ :& schemaToTypes₁ me'
  EmptyME → Nil
  _ → error "schemaToTypes: unexpected MExp within ConsME"

rowToDFRow :: (Pretty r) ⇒ 𝐿 (Type r) → 𝐿 𝕊 → 𝐿 Val
rowToDFRow Nil Nil = Nil
rowToDFRow (τ:&τs) (s:&ss) = case τ of
  ℕT → NatV (read𝕊 s) :& rowToDFRow τs ss
  ℕˢT _ → NatV (read𝕊 s) :& rowToDFRow τs ss
  ℝT → RealV (read𝕊 s) :& rowToDFRow τs ss
  ℝˢT _ → RealV (read𝕊 s) :& rowToDFRow τs ss
  𝕊T → StrV (read𝕊 s) :& rowToDFRow τs ss
  𝔻T τ' → rowToDFRow (τ':&τs) (s:&ss)
  _ → error $ "rowToDFRow: type is currently not supported" ⧺ pprender τ
rowToDFRow y z = error $ "rowToDFRow: arguments length mismatch" ⧺ (pprender (y :* z))

csvToDF ∷ (Pretty r) ⇒ 𝐿 (𝐿 𝕊) → 𝐿 (Type r) → Val
csvToDF sss τs =
  let csvList ∷ 𝐿 (𝐿 Val) = map (rowToDFRow τs) sss
  in MatrixV $ fromLists csvList

csvToMatrix𝔻 ∷ 𝐿 (𝐿 𝕊) → ExMatrix 𝔻
csvToMatrix𝔻 sss =
  let csvList ∷ 𝐿 (𝐿 𝔻) = mapp read𝕊 sss
  in fromLists csvList

partition ∷ 𝐿 Val → 𝐿 (Val ∧ 𝐿 (𝐿 Val)) → 𝐿 (Val ∧ 𝐿 (𝐿 Val))
partition _ Nil = Nil
partition Nil _ = Nil
partition (k:&ks) (v:&vs) = (k :* partition₁ k (v:&vs)) :& partition ks (v:&vs)

partition₁ ∷ Val → 𝐿 (Val ∧ 𝐿 (𝐿 Val)) → 𝐿 (𝐿 Val)
partition₁ k Nil = Nil
partition₁ k ((val:*llvals):&vs) = case k ≡ val of
  True → llvals ⧺ partition₁ k vs
  False → partition₁ k vs

-- this could be moved to Syntax.hs, and PArgs r (and its Eq and Ord instances)
-- could be derived using this type
newtype ExPriv (e ∷ PRIV → ★) = ExPriv { unExPriv ∷ Ex_C PRIV_C e }

deriving instance (∀ p. Show (e p)) ⇒ Show (ExPriv e)

instance (∀ p. Eq (e p)) ⇒ Eq (ExPriv e) where
  ExPriv (Ex_C (e₁ ∷ e p₁)) ==  ExPriv (Ex_C (e₂ ∷ e p₂)) = case eqPRIV (priv @ p₁) (priv @ p₂) of
    Some (Refl ∷ p₁ ≟ p₂) → (e₁ ∷ e p₁) ≡ (e₂ ∷ e p₁)
    None → False

instance (∀ p. Eq (e p),∀ p. Ord (e p)) ⇒ Ord (ExPriv e) where
  ExPriv (Ex_C (e₁ ∷ e p₁)) `compare`  ExPriv (Ex_C (e₂ ∷ e p₂)) = case eqPRIV (priv @ p₁) (priv @ p₂) of
    Some (Refl ∷ p₁ ≟ p₂) → (e₁ ∷ e p₁) ⋚ (e₂ ∷ e p₁)
    None → stripPRIV (priv @ p₁) ⋚ stripPRIV (priv @ p₂)

-- | Defining Val algebraic data type
data Val =
  NatV ℕ
  | RealV 𝔻
  | PairV (Val ∧ Val)
  | StrV 𝕊
  | BoolV 𝔹
  | ListV (𝐿 Val)
  | SetV (𝑃 Val)
  | SFunV 𝕏 (ExPriv SExp) Env  -- See UVMHS.Core.Init for definition of Ex
  | PFunV (𝐿 𝕏) (ExPriv PExp) Env
  | MatrixV (ExMatrix Val)
  deriving (Eq,Ord,Show)

deriving instance Ord (ExMatrix a)
deriving instance Show (ExMatrix a)

instance Eq (Sℕ32 n) where
  TRUSTME_Sℕ32 n₁ == TRUSTME_Sℕ32 n₂ = n₁ ≡ n₂
instance Eq (Bᴍ m n a) where
  Bᴍ m₁ n₁ a₁ == Bᴍ m₂ n₂ a₂ = (m₁ ≡ m₂) ⩓ (n₁ ≡ n₂) ⩓ (a₁ ≡ a₂)
data ExMatrix a where
  ExMatrix ∷ Bᴍ m n a -> ExMatrix a
instance Eq (ExMatrix a) where
  ExMatrix (Bᴍ m₁ n₁ a₁) == ExMatrix (Bᴍ m₂ n₂ a₂) = Bᴍ m₁ n₁ a₁ ≡ Bᴍ m₂ n₂ a₂

ex2m :: ExMatrix a → Bᴍ m n a
ex2m (ExMatrix (Bᴍ m n a)) = Bᴍ m n a

n2i :: ℕ → 𝕀32 n
n2i n = case (d𝕚 (TRUSTME_Sℕ32 (𝕟32 (n+1))) (𝕟32 n)) of
  Some x → x
  None → error "error creating index value"

instance Pretty Val where
  pretty = \case
    NatV n → pretty n
    RealV d → pretty d
    StrV s → pretty s
    BoolV b → pretty b
    ListV l → pretty l
    SetV s → pretty s
    PairV a → pretty a
    SFunV x se e → ppKeyPun "<sλ value>"
    PFunV xs pe e → ppKeyPun "<pλ value>"
    MatrixV m → ppVertical $ list [ppText "MATRIX VALUE:",pretty m]

-- | Converts and integer to a 𝔻
intDouble ∷ ℕ → 𝔻
intDouble = dbl

-- | Converts a natural number to a double
mkDouble ∷ ℕ → 𝔻
mkDouble = dbl

-- | Evaluates an expression from the sensitivity language
seval ∷ (PRIV_C p) ⇒ (Env) → (SExp p) → (Val)

-- literals
seval _ (ℕSE n)        = NatV n
seval _ (ℝSE n)        = RealV n
seval _ (ℝˢSE n)       = RealV n
seval _ (ℕˢSE n)       = NatV n
seval env (RealSE e) =
  case (seval env $ extract e) of
    (NatV n) → RealV $ mkDouble n

-- variables
seval env (VarSE x) = env ⋕! x
-- | x ∈ env
-- | otherwise = error $ "Unknown variable: " ⧺ (show𝕊 x) ⧺ " in environment with bound vars " ⧺ (show𝕊 $ keys env)

seval env (LetSE x e₁ e₂) = do
  let v₁ = seval env (extract e₁) in
    seval ((x ↦ v₁) ⩌ env) (extract e₂)

-- arithmetic
seval env (PlusSE e₁ e₂) =
  case (seval env (extract e₁), seval env (extract e₂)) of
    (MatrixV v₁, MatrixV v₂) → MatrixV $ map RealV ( (map urv v₁) +++ (map urv v₂) )
    (RealV v₁, RealV v₂) → RealV (v₁ + v₂)
    (NatV v₁, NatV v₂) → NatV (v₁ + v₂)
    (a, b) → error $ "No pattern for " ⧺ (show𝕊 (a, b))

seval env (MinusSE e₁ e₂) =
  case (seval env (extract e₁), seval env (extract e₂)) of
    (MatrixV v₁, MatrixV v₂) → MatrixV $ map RealV ( (map urv v₁) -/ (map urv v₂) )
    (RealV v₁, RealV v₂) → RealV (v₁ - v₂)
    (NatV v₁, NatV v₂) → NatV (v₁ - v₂)
    (a, b) → error $ "No pattern for " ⧺ (show𝕊 (a, b))

seval env (TimesSE e₁ e₂) =
  case (seval env (extract e₁), seval env (extract e₂)) of
    (MatrixV v₁, MatrixV v₂) → MatrixV $ map RealV ((map urv v₁) <> (map urv v₂))
    (RealV v₁, MatrixV v₂) → MatrixV $ map RealV (mscale v₁ (map urv v₂))
    (RealV v₁, RealV v₂) → RealV (v₁ × v₂)
    (NatV v₁, NatV v₂) → NatV (v₁ × v₂)
    (a, b) → error $ "No pattern for " ⧺ (show𝕊 (a, b))

seval env (DivSE e₁ e₂) =
  case (seval env (extract e₁), seval env (extract e₂)) of
    (RealV v₁, RealV v₂) → RealV (v₁ / v₂)
    (a, b) → error $ "No pattern for " ⧺ (show𝕊 (a, b))

-- matrix operations
seval env (MRowsSE e) =
  case (seval env (extract e)) of
    (MatrixV v) →
      NatV $ nat $ rows v

seval env (MColsSE e) =
  case (seval env (extract e)) of
    (MatrixV v) →
      NatV $ nat $ cols v

seval env (MIndexSE e₁ e₂ e₃) =
  case (seval env (extract e₁),seval env (extract e₂),seval env (extract e₃)) of
    (MatrixV v, NatV n₁, NatV n₂) →
      indexBᴍ (n2i n₁) (n2i n₂) (ex2m v)


seval env (IdxSE e) =
  case (seval env (extract e)) of
    (NatV d) →
      let posMat ∷ ExMatrix 𝔻 = ident d
          negMat ∷ ExMatrix 𝔻 = mscale (neg one) posMat
      in MatrixV (map RealV (posMat === negMat))

-- seval env (SMTrE e) =
--   case seval env e of (MatrixV m) → MatrixV $ tr m

-- clip operation for only L2 norm
seval env (MClipSE norm e) =
  case (norm, seval env (extract e)) of
    (L2,   MatrixV v) →  MatrixV $ map RealV $ fromRows (map normalize $ toRows $ map urv v)
    (LInf, MatrixV v) →  MatrixV $ map RealV $ fromRows (map normalize $ toRows $ map urv v)
    (l, _) → error $ "Invalid norm for clip: " ⧺ (show𝕊 l)

-- gradient
seval env (MLipGradSE LR e₁ e₂ e₃) =
  case (seval env (extract e₁), seval env (extract e₂), seval env (extract e₃)) of
    (MatrixV θ, MatrixV xs, MatrixV ys) →
      case ((rows θ ≡ 1) ⩓ (cols ys ≡ 1)) of
        True →
          let θ'  ∷ DuetVector 𝔻 = flatten (map urv θ)
              ys' ∷ DuetVector 𝔻 = flatten (map urv ys)
          in MatrixV $ map RealV $ asRow $ ngrad θ' (map urv xs) ys'
        False →
          error $ "Incorrect matrix dimensions for gradient: " ⧺ (show𝕊 (rows θ, cols ys))
    (a, b, c) → error $ "No pattern for " ⧺ (show𝕊 (a, b, c))

-- create matrix
seval env (MCreateSE l e₁ e₂ i j e₃) =
  case (seval env (extract e₁), seval env (extract e₂)) of
    (NatV v₁, NatV v₂) →
      let row = replicate v₂ 0.0
          m = replicate v₁ row
          m₁ = fromRows m
      in MatrixV (map RealV m₁)

-- matrix maps
seval env (MMapSE e₁ x e₂) =
  case (seval env (extract e₁)) of
    (MatrixV v₁) →
      MatrixV $ map (\a → (seval ((x ↦ a) ⩌ env) (extract e₂))) v₁

seval env (MMap2SE e₁ e₂ x₁ x₂ e₃) =
  case (seval env (extract e₁),seval env (extract e₂)) of
    (MatrixV v₁, MatrixV v₂) →
      let fn = zipWith (zipWith (\a b → (seval ((x₂ ↦ b) ⩌ ((x₁ ↦ a) ⩌ env)) (extract e₃))))
          v₁' = toRows v₁
          v₂' = toRows v₂
          c = fn v₁' v₂'
      in MatrixV $ fromRows c

-- functions and application
seval env (PFunSE _ args body) =
  PFunV (map fst args) (ExPriv (Ex_C (extract body))) env

seval env (SFunSE x _ body) =
  SFunV x (ExPriv (Ex_C (extract body))) env

seval env (BoxSE e) = seval env (extract e)

seval env (UnboxSE e) = seval env (extract e)

seval env TrueSE = BoolV True

seval env FalseSE = BoolV False

-- TODO: this is supposed to clip the vector that e evaluates to such that the norm
-- of the ouptut vector is 1. (only do this if the norm is > 1)
seval env (ClipSE e) = seval env (extract e)

seval env (ConvSE e) = seval env (extract e)

seval env (DiscSE e) = seval env (extract e)

seval env (AppSE e₁ e₂) =
  case seval env (extract e₁) of
    (SFunV x (ExPriv (Ex_C body)) env') →
      let env'' = (x ↦ (seval env (extract e₂))) ⩌ env'
      in seval env'' body

seval env (SetSE es) = SetV $ pow $ map ((seval env) ∘ extract) es

seval env (TupSE e₁ e₂) = PairV $ seval env (extract e₁) :* seval env (extract e₂)

seval env (MemberSE e₁ e₂) = case (seval env (extract e₁), seval env (extract e₂)) of
  (v, SetV p) → BoolV $ v ∈ p

seval env (UnionAllSE e) = case (seval env (extract e)) of
  (SetV ss) → SetV $ fold pø (∪) $ pmap (\(SetV p) → p) ss

seval env (JoinSE e₁ e₂ e₃ e₄) =
  case (seval env (extract e₁),seval env (extract e₂),seval env (extract e₃),seval env (extract e₄)) of
    (MatrixV m₁, NatV n₁, MatrixV m₂, NatV n₂) →
      let colmaps = map (\row₁ → joinMatch₁ n₁ (buildRows (list [row₁])) (map (\l → (buildRows (list [l]))) (toLists m₂)) n₂) (toLists m₁)
          colmaps₁ = filter (\colmap → not (colmap ≡ Nil)) $ colmaps
      in MatrixV $ buildRows $ list colmaps₁

-- seval env (CSVtoMatrixSE s _) =
--   let csvList ∷ 𝐿 (𝐿 𝔻) = mapp read𝕊 s
--       m ∷ ExMatrix 𝔻 = fromLists csvList
--   in MatrixV $ mapp RealV m

seval env (EqualsSE e₁ e₂) =
  let v₁ = seval env $ extract e₁
      v₂ = seval env $ extract e₂
  in BoolV $ v₁ ≡ v₂

seval env e = error $ "Unknown expression: " ⧺ (show𝕊 e)

-- | Evaluates an expression from the privacy language
peval ∷ (PRIV_C p) ⇒ Env → PExp p → IO (Val)

-- bind and application
peval env (BindPE x e₁ e₂) = do
  v₁ ← peval env (extract e₁)
  v₂ ← peval ((x ↦ v₁) ⩌ env) (extract e₂)
  return v₂

peval env (IfPE e₁ e₂ e₃) = case seval env (extract e₁) of
  BoolV True → peval env (extract e₂)
  BoolV False → peval env (extract e₃)

-- peval env (AppPE f _ as) =
--   case seval env (extract f) of
--     (PFunV args body env') →
--       let vs    ∷ 𝐿 Val = map ((seval env) ∘ extract) as
--           env'' ∷ Env = fold env' (\(var :* val) → (⩌ (var ↦ val))) (zip args vs)
--       in peval env'' body

-- sample on two matrices and compute on sample
peval env (EDSamplePE size xs ys x y e) =
  case (seval env (extract size), seval env (extract xs), seval env (extract ys)) of
    (NatV n, MatrixV v1, MatrixV v2) →
      sampleHelper n (map urv v1) (map urv v2) x y (extract e) env

peval env (TCSamplePE size xs ys x y e) =
  case (seval env (extract size), seval env (extract xs), seval env (extract ys)) of
    (NatV n, MatrixV v1, MatrixV v2) →
      sampleHelper n (map urv v1) (map urv v2) x y (extract e) env

peval env (RenyiSamplePE size xs ys x y e) =
  case (seval env (extract size), seval env (extract xs), seval env (extract ys)) of
    (NatV n, MatrixV v1, MatrixV v2) →
      sampleHelper n (map urv v1) (map urv v2) x y (extract e) env

-- gaussian mechanism for real numbers
peval env (GaussPE r (EDGaussParams ε δ) vs e) =
  case (seval env (extract r), seval env (extract ε), seval env (extract δ), seval env (extract e)) of
    (RealV r', RealV ε', RealV δ', RealV v) → do
      r ← gaussianNoise zero (r' × (root $ 2.0 × (log $ 1.25/δ')) / ε')
      return $ RealV $ v + r
    (a, b, c, d) → error $ "No pattern for: " ⧺ (show𝕊 (a,b,c,d))

-- laplace mechanism for real numbers
peval env (LaplacePE r (EpsLaplaceParams ε) vs e) =
  case (seval env (extract r), seval env (extract ε), seval env (extract e)) of
    (RealV r', RealV ε', RealV v) → do
      r ← laplaceNoise (r' / ε')
      return $ RealV $ v + r
    (a, b, c) → error $ "No pattern for: " ⧺ (show𝕊 (a,b,c))

-- gaussian mechanism for matrices
peval env (MGaussPE r (EDGaussParams ε δ) vs e) =
  case (seval env (extract r), seval env (extract ε), seval env (extract δ), seval env (extract e)) of
    (RealV r', RealV ε', RealV δ', MatrixV mat) → do
      let σ = (r' × (root $ 2.0 × (log $ 1.25/δ')) / ε')
      mat' ← mapM (\row → mapM (\val → gaussianNoise val σ) row) $ toLists (map urv mat)
      return $ MatrixV $ (map RealV (fromLists mat'))
    (a, b, c, d) → error $ "No pattern for: " ⧺ (show𝕊 (a,b,c,d))

peval env (MGaussPE r (RenyiGaussParams α ϵ) vs e) =
  case (seval env (extract r), seval env (extract α), seval env (extract ϵ), seval env (extract e)) of
    (RealV r', NatV α', RealV ϵ', MatrixV mat) → do
      let σ = (r' × (root (dbl α'))) / (root (2.0 × ϵ'))
      mat' ← mapM (\row → mapM (\val → gaussianNoise val σ) row) $ toLists (map urv mat)
      return $ MatrixV $ (map RealV (fromLists mat'))
    (a, b, c, d) → error $ "No pattern for: " ⧺ (show𝕊 (a,b,c,d))

peval env (MGaussPE r (TCGaussParams ρ ω) vs e) =
  case (seval env (extract r), seval env (extract ρ), seval env (extract ω), seval env (extract e)) of
    (RealV r', RealV ρ', NatV ω', MatrixV mat) → do
      gn ← gaussianNoise 0.0 ((8.0 × r' × r') / ρ')
      let a = 8.0 × r' × (dbl ω')
      let σ =  a × (arsinh $ (1.0 / a) × gn)
      mat' ← mapM (\row → mapM (\val → gaussianNoise val σ) row) $ toLists (map urv mat)
      return $ MatrixV $ (map RealV (fromLists mat'))
    (a, b, c, d) → error $ "No pattern for: " ⧺ (show𝕊 (a,b,c,d))

-- evaluate finite iteration
peval env (LoopPE k init xs x₁ x₂ e) =
  case (seval env (extract k), seval env (extract init)) of
    (NatV k', initV) →
      iter₁ k' initV x₁ x₂ 0 (extract e) env

peval env (EDLoopPE _ k init xs x₁ x₂ e) =
  case (seval env (extract k), seval env (extract init)) of
    (NatV k', initV) →
      iter₁ k' initV x₁ x₂ 0 (extract e) env

peval env (ParallelPE e₀ e₁ x₂ e₂ x₃ x₄ e₃) =
  case (seval env (extract e₀), seval env (extract e₁)) of
    (MatrixV m, SetV p) → do
      let candidates ∷ 𝐿 (Val ∧ 𝐿 (𝐿 Val)) = map (\row → (seval ((x₂ ↦ MatrixV (fromRows (list [row]))) ⩌ env) (extract e₂)) :* (list [row])) (toLists m)
      let parts ∷ 𝐿 (Val ∧ 𝐿 (𝐿 Val)) = partition (list (uniques p)) $ list $ filter (\x → (fst x) ∈ p) candidates
      let parts₁ = filter (\(v:*llvs) → not (llvs ≡ Nil)) parts
      r ← pow ^$ mapM (\(v :* llvals) → (peval ((x₃ ↦ v) ⩌ (x₄ ↦ MatrixV (fromRows llvals)) ⩌ env) (extract e₃))) parts₁
      return $ SetV $ r

-- evaluate sensitivity expression and return in the context of the privacy language
peval env (ReturnPE e) =
  return $ seval env (extract e)

-- exponential mechanism
-- peval env (ExponentialPE s ε xs _ x body) =
--   case (seval env s, seval env ε, seval env xs) of
--     (RealV s', RealV ε', MatrixV xs') →
--       let xs''     = map (\row' → fromLists [row']) $ toLists xs'
--           envs     = map (\m → (x ↦ (MatrixV m)) ⩌ env) xs''
--           getScore = \env1 → case seval env1 (extract body) of
--             (RealV   r) → r
--             (MatrixV m) | size m == (1, 1) → head $ head $ toLists m
--             a → error $ "Invalid score: " ⧺ (chars $ show𝕊 a)
--           scores   = map getScore envs
--           δ'       = 1e-5
--           σ        = (s' × (root $ 2.0 × (log $ 1.25/δ')) / ε')
--       in do
--         scores' ← mapM (\score → gaussianNoise score σ) scores
--         return $ MatrixV $ minElem (zip xs'' scores')

-- error
peval env e = error $ "Unknown expression: " ⧺ (show𝕊 e)


-- | Helper function for loop expressions
iter₁ ∷ (PRIV_C p) ⇒ ℕ → Val → 𝕏 → 𝕏 → ℕ → PExp p → Env → IO (Val)
iter₁ 0 v _ _ _ _ _ = return v
iter₁ k v t x kp body env = do
  newVal ← peval ((x ↦ v) ⩌ ((t ↦ (NatV $ nat kp)) ⩌ env)) body
  iter₁ (k - 1) newVal t x (kp+1) body env

-- | Empty environment
emptyEnv ∷ Env
emptyEnv = dø

-- | Samples a normal distribution and returns a single value
gaussianNoise ∷ 𝔻 → 𝔻 → IO 𝔻
gaussianNoise c v = normalIO'(c, v)

laplaceNoise ∷ 𝔻 → IO 𝔻
laplaceNoise scale = do
  gen ← createSystemRandom
  u ← uniformR (neg 0.5, 0.5) gen
  return $ neg $ scale × (signum u) × log(1.0 - 2.0 × (abs u))

-- | Helper function for PSampleE
sampleHelper :: (PRIV_C p) ⇒ ℕ → ExMatrix 𝔻 → ExMatrix 𝔻 → 𝕏 → 𝕏 → PExp p → Env → IO Val
sampleHelper n xs ys x y e env = do
  batch <- minibatch (int n) xs (flatten ys)
  peval (insertDataSet env (x :* y) ((fst batch) :* (snd batch))) e

insertDataSet ∷ Env → (𝕏 ∧ 𝕏) → (ExMatrix 𝔻 ∧ ExMatrix 𝔻) → Env
insertDataSet env (x :* y) (xs :* ys) =
  (x ↦ (MatrixV $ map RealV $ xs)) ⩌ (y ↦ (MatrixV $ map RealV ys)) ⩌ env

type Model = DuetVector 𝔻

-- | Averages LR gradient over the whole matrix of examples
ngrad ∷ Model → ExMatrix 𝔻 → DuetVector 𝔻 → DuetVector 𝔻
ngrad θ x y =
  let θ'       = asColumn θ
      y'       = asColumn y
      exponent = (x <> θ') × y'
      scaled   = y' × (map (\x → 1.0/(exp(x)+1.0) ) exponent)
      gradSum  = (tr x) <> scaled
      avgGrad  ∷ DuetVector 𝔻 = flatten $ mscale (1.0/(dbl $ rows x)) gradSum
  in (scale (neg one) avgGrad)

-- | Obtains a vector in the same direction with L2-norm=1
normalize :: DuetVector 𝔻 → DuetVector 𝔻
normalize v
  | r > 1.0     =  scale (1.0/r) v
  | otherwise =  v
  where
    r = norm_2 v

-- | Makes a single prediction
predict ∷ Model → (DuetVector 𝔻 ∧ 𝔻) → 𝔻
predict θ (x :* y) = signum $ x <.> θ

-- dot product
(<.>) :: DuetVector 𝔻 → DuetVector 𝔻 → 𝔻
(<.>) a b = sum $ zipWith (×) a b

signum ∷ (Ord a, Zero a, Zero p, Minus p, One p) ⇒ a → p
signum x = case compare x zero of
  LT → neg one
  EQ → zero
  GT → one

abs ∷ (Ord p, Zero p, Minus p) ⇒ p → p
abs x = case compare x zero of
  LT → neg x
  EQ → zero
  GT → x

isCorrect ∷ (𝔻 ∧ 𝔻) → (ℕ ∧ ℕ)
isCorrect (prediction :* actual) | prediction ≡ actual = (1 :* 0)
                                 | otherwise = (0 :* 1)

-- | Calculates the accuracy of a model
accuracy ∷ ExMatrix 𝔻 → DuetVector 𝔻 → Model → (ℕ ∧ ℕ)
accuracy x y θ = let pairs ∷ 𝐿 (DuetVector 𝔻 ∧ 𝔻) = list $ zip (map normalize $ toRows x) (toList y)
                     labels ∷ 𝐿 𝔻 = map (predict θ) pairs
                     correct ∷ 𝐿 (ℕ ∧ ℕ) = map isCorrect $ list $ zip labels (toList y)
                 in fold (0 :* 0) (\a b → ((fst a + fst b) :* (snd a + snd b))) correct

-- | Generates random indicies for sampling
randIndices :: ℤ → ℤ → ℤ → GenIO → IO (𝐿 ℤ)
randIndices n a b gen
  | n ≡ zero    = return Nil
  | otherwise = do
      x <- uniformR (intΩ64 a, intΩ64 b) gen
      xs' <- randIndices (n - one) a b gen
      return (int x :& xs')

-- | Outputs a single minibatch of data
minibatch :: ℤ → ExMatrix 𝔻 → DuetVector 𝔻 → IO (ExMatrix 𝔻 ∧ ExMatrix 𝔻)
minibatch batchSize xs ys = do
  gen <- createSystemRandom
  idxs <- randIndices batchSize zero (𝕫 (rows xs) - one) gen
  let bxs = xs ? idxs
      bys = ((asColumn ys) ? idxs)
  return (bxs :* bys)
