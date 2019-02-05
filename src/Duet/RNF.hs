module Duet.RNF where

import Duet.UVMHS

instance Show FullContext where
  show = chars ∘ ppshow

instance Show RExpPre where
  show = chars ∘ ppshow

type RExp = Annotated FullContext RExpPre
data RExpPre =
    VarRE 𝕏
  | NatRE ℕ
  | NNRealRE 𝔻
  | MaxRE RExp RExp
  | MinRE RExp RExp
  | PlusRE RExp RExp
  | TimesRE RExp RExp
  | DivRE RExp RExp
  | RootRE RExp
  | LogRE RExp
  | MinusRE RExp RExp
  deriving (Eq,Ord)
makePrettySum ''RExpPre

interpRExp ∷ (𝕏 ⇰ 𝔻) → RExpPre → 𝔻
interpRExp γ = \case
  VarRE x → γ ⋕! x
  NatRE n → dbl n
  NNRealRE r → r
  MaxRE e₁ e₂ → interpRExp γ (extract e₁) ⩏ interpRExp γ (extract e₂)
  MinRE e₁ e₂ → interpRExp γ (extract e₁) ⩎ interpRExp γ (extract e₂)
  PlusRE e₁ e₂ → interpRExp γ (extract e₁) + interpRExp γ (extract e₂)
  TimesRE e₁ e₂ → interpRExp γ (extract e₁) × interpRExp γ (extract e₂)
  DivRE e₁ e₂ → interpRExp γ (extract e₁) / interpRExp γ (extract e₂)
  RootRE e → root $ interpRExp γ $ extract e
  LogRE e → log $ interpRExp γ $ extract e
  MinusRE e₁ e₂ → interpRExp γ (extract e₁) - interpRExp γ (extract e₂)

data RNF = 
    NatRNF ℕ
  | NNRealRNF 𝔻
  | SymRNF (𝑃 {- max -} (𝑃 {- min -} RSP))
  deriving (Eq,Ord,Show)
newtype RSP = RSP { unRSP ∷ (RAtom ⇰ {- prod -} ℕ) ⇰ {- sum -} ℕ }
  deriving (Eq,Ord,Show)
data RAtom =
    NNRealRA 𝔻
  | VarRA 𝕏
  | InvRA RSP
  | RootRA RSP
  | LogRA RSP
  | MinusRA RNF RNF
  deriving (Eq,Ord,Show)

makePrisms ''RNF

instance HasPrism RNF ℕ where hasPrism = natRNFL
instance HasPrism RNF 𝔻 where hasPrism = nNRealRNFL

ppRAtom ∷ RAtom → Doc
ppRAtom = \case
  VarRA x → pretty x
  NNRealRA r → pretty r
  InvRA e → ppAtLevel 7 $ concat [ppOp "1/",ppRSP e]
  RootRA e → ppAtLevel 7 $ concat [ppOp "√",ppRSP e]
  LogRA e → ppAtLevel 7 $ concat [ppOp "㏒",ppRSP e]
  MinusRA e₁ e₂ → ppAtLevel 5 $ concat [ppRNF e₁,ppOp "-",ppBump $ ppRNF e₂]

ppProd ∷ (RAtom ⇰ ℕ) → Doc
ppProd xs = case list xs of
  Nil → pretty 1
  (x :* n) :& Nil → 
    case n ≡ 1 of
      True → ppRAtom x
      False → ppAtLevel 7 $ concat [ppRAtom x,ppOp "^",pretty n]
  _ → ppAtLevel 6 $ concat $ do
        (x :* n) ← list xs
        return $ 
          case n ≡ 1 of
            True → ppRAtom x
            False → ppAtLevel 7 $ concat [ppRAtom x,ppOp "^",pretty n]

ppSum ∷ (RAtom ⇰ ℕ) ⇰ ℕ → Doc
ppSum xs² = case list xs² of
  Nil → pretty 0
  (xs :* m) :& Nil → 
      case m ≡ 1 of
        True → ppProd xs
        False → ppAtLevel 6 $ concat [pretty m,ppProd xs]
  _ → ppAtLevel 5 $ concat $ inbetween (ppOp "+") $ do
    (xs :* m) ← list xs²
    return $
      case m ≡ 1 of
        True → ppProd xs
        False → ppAtLevel 6 $ concat [pretty m,ppProd xs]

ppRSP ∷ RSP → Doc
ppRSP = ppSum ∘ unRSP

ppMin ∷ 𝑃 RSP → Doc
ppMin xs³ = case list xs³ of
  Nil → pretty 0
  xs² :& Nil → ppRSP xs²
  _ → ppAtLevel 6 $ concat $ inbetween (ppOp "⊓") $ do
    xs² ← list xs³
    return $ ppRSP xs²

ppMax ∷ 𝑃 (𝑃 RSP) → Doc
ppMax xs⁴ = case list xs⁴ of
  Nil → ppLit "∞"
  xs³ :& Nil → ppMin xs³
  _ → ppAtLevel 5 $ concat $ inbetween (ppOp "⊔") $ do
    xs³ ← list xs⁴
    return $ ppMin xs³

ppRNF ∷ RNF → Doc
ppRNF = \case
  NatRNF n → concat [pretty n]
  NNRealRNF r → concat [pretty r]
  SymRNF xs⁴ → ppMax xs⁴

instance Pretty RNF where pretty = ppRNF

interpRAtom ∷ (𝕏 ⇰ 𝔻) → RAtom → 𝔻
interpRAtom γ = \case
  VarRA x → γ ⋕! x
  NNRealRA r → r
  InvRA xs² → 1.0 / interpRSP γ xs²
  RootRA xs² → root $ interpRSP γ xs²
  LogRA xs² → log $ interpRSP γ xs²
  MinusRA xs⁴ ys⁴ → interpRNF γ xs⁴ - interpRNF γ ys⁴

interpRSP ∷ (𝕏 ⇰ 𝔻) → RSP → 𝔻
interpRSP γ xs² = 
  fold 0.0 (+) $ do
    (xs :* m) ← list $ unRSP xs²
    let d = fold 1.0 (×) $ do
          (x :* n) ← list xs
          return $ interpRAtom γ x ^ dbl n
    return $ d × dbl m

interpRNF ∷ (𝕏 ⇰ 𝔻) → RNF → 𝔻
interpRNF γ = \case
  NatRNF n → dbl n
  NNRealRNF r → r
  SymRNF xs⁴ → 
    fold 0.0 (⩏) $ do
      xs³ ← list xs⁴
      return $ fold (1.0/0.0) (⩎) $ do
        xs² ← list xs³
        return $ interpRSP γ xs²

natSymRNF ∷ ℕ → 𝑃 (𝑃 RSP)
natSymRNF n
  | n ≤ 0 = pø
  | otherwise = single $ single $ RSP $ dø ↦ n

realSymRNF ∷ 𝔻 → 𝑃 (𝑃 RSP)
realSymRNF r = single $ single $ RSP $ (NNRealRA r ↦ 1) ↦ 1

binopRNF ∷ 𝑃 RNF → 𝑃 RNF → (ℕ → ℕ → ℕ ∨ 𝔻) → (𝔻 → 𝔻 → 𝔻) → (𝑃 (𝑃 RSP) → 𝑃 (𝑃 RSP) → 𝑃 (𝑃 RSP)) → RNF → RNF → RNF
binopRNF units zeros nop rop rspop ε₁ ε₂
  | ε₁ ∈ units = ε₂
  | ε₂ ∈ units = ε₁
  | ε₁ ∈ zeros = ε₁
  | ε₂ ∈ zeros = ε₂
  | otherwise = case (ε₁,ε₂) of
    (NatRNF n₁ ,NatRNF n₂ ) → case nop n₁ n₂ of {Inl n → NatRNF n;Inr r → NNRealRNF r}
    (NatRNF n₁ ,NNRealRNF r₂) → NNRealRNF $ rop (dbl n₁) r₂
    (NNRealRNF r₁,NatRNF n₂ ) → NNRealRNF $ rop r₁ $ dbl n₂
    (NatRNF n₁ ,SymRNF ys⁴) → SymRNF $ rspop (natSymRNF n₁) ys⁴
    (SymRNF xs⁴,NatRNF n₂ ) → SymRNF $ rspop xs⁴ $ natSymRNF n₂
    (NNRealRNF r₁,NNRealRNF r₂) → NNRealRNF $ rop r₁ r₂
    (NNRealRNF r₁,SymRNF ys⁴) → SymRNF $ rspop (realSymRNF r₁) ys⁴
    (SymRNF xs⁴,NNRealRNF r₂) → SymRNF $ rspop xs⁴ $ realSymRNF r₂
    (SymRNF xs⁴,SymRNF ys⁴) → SymRNF $ rspop xs⁴ ys⁴

varRNF ∷ 𝕏 → RNF
varRNF x = SymRNF $ single $ single $ RSP $ (VarRA x ↦ 1) ↦ 1

maxRNF ∷ RNF → RNF → RNF
maxRNF = binopRNF (pow [NatRNF 0,NNRealRNF 0.0]) pø (Inl ∘∘ (⩏)) (⩏) $ \ xs⁴ ys⁴ → xs⁴ ∪ ys⁴

minRNF ∷ RNF → RNF → RNF
minRNF = binopRNF pø (pow [NatRNF 0,NNRealRNF 0.0]) (Inl ∘∘ (⩎)) (⩎) $ \ xs⁴ ys⁴ → pow $ do
  xs³ ← list xs⁴
  ys³ ← list ys⁴
  return $ xs³ ⧺ ys³

plusRNF ∷ RNF → RNF → RNF
plusRNF = binopRNF (pow [NatRNF 0,NNRealRNF 0.0]) pø (Inl ∘∘ (+)) (+) $ \ xs⁴ ys⁴ → pow $ do
  xs³ ← list xs⁴
  ys³ ← list ys⁴
  return $ pow $ do
    xs² ← list xs³
    ys² ← list ys³
    return $ RSP $ unionWith (+) (unRSP xs²) (unRSP ys²)

timesRNF ∷ RNF → RNF → RNF
timesRNF = binopRNF (pow [NatRNF 1,NNRealRNF 1.0]) (pow [NatRNF 0,NNRealRNF 0.0]) (Inl ∘∘ (×)) (×) $ \ xs⁴ ys⁴ → pow $ do
  xs³ ← list xs⁴
  ys³ ← list ys⁴
  return $ pow $ do
    xs² ← list xs³
    ys² ← list ys³
    return $ RSP $ dict $ do
      (xs :* m) ← list $ unRSP xs²
      (ys :* n) ← list $ unRSP ys²
      return $ unionWith (+) xs ys ↦ m×n

expRNF ∷ RNF → ℕ → RNF
expRNF e = \case
  0 → NatRNF 1
  n → timesRNF e (expRNF e (n - 1))

invRNF ∷ RNF → RNF
invRNF (NatRNF n) = NNRealRNF $ 1.0 / dbl n
invRNF (NNRealRNF r) = NNRealRNF $ 1.0 / r
invRNF (SymRNF xs⁴) = SymRNF $ pow $ do
  xs³ ← cart $ map list $ list xs⁴
  return $ pow $ do
    xs² ← xs³
    return $ RSP $ (InvRA xs² ↦ 1) ↦ 1

rootRNF ∷ RNF → RNF
rootRNF (NatRNF n) = NNRealRNF $ root $ dbl n
rootRNF (NNRealRNF r) = NNRealRNF $ root $ r
rootRNF (SymRNF xs⁴) = SymRNF $ pow $ do
  xs³ ← list xs⁴
  return $ pow $ do
    xs² ← list xs³
    return $ RSP $ case dmin $ unRSP xs² of
      -- Some (m :* xs :* xs²') | xs²' ≡ dø →
      --   let blah = undefined
      --       -- xs' = dict $ do
      --       --   n :* x ← list xs
      --       --   return $ RootRA ((n :* x) ↦ n 
      --   in undefined -- blah ↦ m
      _ → (RootRA xs² ↦ 1) ↦ 1

logRNF ∷ RNF → RNF
logRNF (NatRNF n) = NNRealRNF $ log $ dbl n
logRNF (NNRealRNF r) = NNRealRNF $ log $ r
logRNF (SymRNF xs⁴) = SymRNF $ pow $ do
  xs³ ← list xs⁴
  return $ pow $ do
    xs² ← list xs³
    return $ RSP $ (LogRA xs² ↦ 1) ↦ 1

minusRNF ∷ RNF → RNF → RNF
minusRNF xs⁴ ys⁴ = SymRNF $ single $ single $ RSP $ (MinusRA xs⁴ ys⁴ ↦ one) ↦ one

instance Bot RNF where bot = NatRNF 0
instance Join RNF where (⊔) = maxRNF
instance JoinLattice RNF

instance Meet RNF where (⊓) = maxRNF

instance Zero RNF where zero = NatRNF 0
instance Plus RNF where (+) = plusRNF
instance Minus RNF where (-) = minusRNF
instance One RNF where one = NatRNF 1
instance Times RNF where (×) = timesRNF
instance Divide RNF where e₁ / e₂ = e₁ `timesRNF` invRNF e₂
instance Root RNF where root = rootRNF
instance Log RNF where log = logRNF

instance Multiplicative RNF
instance Additive RNF

instance Null RNF where null = zero
instance Append RNF where (⧺) = (+)
instance Monoid RNF

instance POrd RNF where
  NatRNF    n₁  ⊑ NatRNF    n₂  = n₁ ≤ n₂
  NatRNF    n₁  ⊑ NNRealRNF r₂  = dbl n₁ ≤ r₂
  NNRealRNF r₁  ⊑ NatRNF    n₂  = r₁ ≤ dbl n₂
  NatRNF    n₁  ⊑ SymRNF    ys⁴ = natSymRNF n₁ ⊆ ys⁴
  SymRNF    xs⁴ ⊑ NatRNF    n₂  = xs⁴ ⊆ natSymRNF n₂
  NNRealRNF r₁  ⊑ NNRealRNF r₂  = r₁ ≤ r₂
  NNRealRNF r₁  ⊑ SymRNF    ys⁴ = realSymRNF r₁ ⊆ ys⁴
  SymRNF    xs⁴ ⊑ NNRealRNF r₂  = xs⁴ ⊆ realSymRNF r₂
  SymRNF    xs⁴ ⊑ SymRNF    ys⁴ = xs⁴ ⊆ ys⁴

normalizeRExpPre ∷ RExpPre → RNF
normalizeRExpPre (VarRE x) = varRNF x
normalizeRExpPre (NatRE n) = NatRNF n
normalizeRExpPre (NNRealRE r) = NNRealRNF r
normalizeRExpPre (MaxRE e₁ e₂) = maxRNF (normalizeRExpPre $ extract e₁) (normalizeRExpPre $ extract e₂)
normalizeRExpPre (MinRE e₁ e₂) = minRNF (normalizeRExpPre $ extract e₁) (normalizeRExpPre $ extract e₂)
normalizeRExpPre (PlusRE e₁ e₂) = plusRNF (normalizeRExpPre $ extract e₁) (normalizeRExpPre $ extract e₂)
normalizeRExpPre (TimesRE e₁ e₂) = timesRNF (normalizeRExpPre $ extract e₁) (normalizeRExpPre $ extract e₂)
normalizeRExpPre (DivRE e₁ e₂) = timesRNF (normalizeRExpPre $ extract e₁) $ invRNF (normalizeRExpPre $ extract e₂)
normalizeRExpPre (RootRE e) = rootRNF (normalizeRExpPre $ extract e)
normalizeRExpPre (LogRE e) = logRNF (normalizeRExpPre $ extract e)
normalizeRExpPre (MinusRE e₁ e₂) = minusRNF (normalizeRExpPre $ extract e₁) (normalizeRExpPre $ extract e₂)

normalizeRExp ∷ RExp → RNF
normalizeRExp = normalizeRExpPre ∘ extract
