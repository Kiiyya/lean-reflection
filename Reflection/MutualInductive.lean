import Lean -- not essential: only for `Lean.Meta.getEqnsFor?` later
import Reflection.Util.EqHelpers

namespace Reflection.MutualInductive
/-
  Adaptation of https://dx.doi.org/10.4230/LIPIcs.FSCD.2020.23 for Lean4.
  Agda source for the above lives at https://bitbucket.org/javra/inductive-families
-/

set_option pp.proofs true
set_option pp.fieldNotation false


-- # Syntax

/-- Example for `Nat` is `U`, for `Vec` is `SPi Nat (fun n => U)`. -/
inductive Tyₛ : Type (u + 1)
| U : Tyₛ
| SPi : (T : Type u) -> (T -> Tyₛ) -> Tyₛ
open Tyₛ

-- cursed approach to avoid u+1 (credits to Jakob)
-- inductive Tyₛ' (Ts : List (Type u)) : Type u
-- | U : Tyₛ' Ts
-- | SPi : (i : Fin (Ts.length)) -> (T[i] -> Tyₛ' Ts) -> Tyₛ' Ts

inductive Conₛ
| nil : Conₛ
| ext : Conₛ -> Tyₛ -> Conₛ
notation "⬝" => Conₛ.nil
infixr:67 " ▹ " => Conₛ.ext

/-- De-brujin variable referring to an entry in the context.
A context is for example `["Even", "Odd"]`, then `.vz` refers to `"Even"`.
These are nameless, the quotations are only to ease explanation. -/
inductive Varₛ : Conₛ -> Tyₛ -> Type (u+1)
| vz :               Varₛ (Γₛ ▹ Aₛ) Aₛ
| vs : Varₛ Γₛ Aₛ -> Varₛ (Γₛ ▹ Bₛ) Aₛ
open Varₛ

set_option genInjectivity false in
/-- `t : Tmₛ Γ A` corresponds to `Γ ⊢ t : A`.
Original Agda: https://bitbucket.org/javra/inductive-families/src/717f404c220e17d0ac5917306fd74dd0c4883cde/agda/IF.agda#lines-25:27 -/
inductive Tmₛ.{u} : Conₛ.{u} -> Tyₛ.{u} -> Type (u+1)
/-- A variable is a term.
```-
(a : A) ∈ Γ
-----------var
Γ ⊢ₛ a : A
``` -/
| var : Varₛ Γ A -> Tmₛ Γ A
/-- Function application.
```-
Γ ⊢ₛ f : (x : T) -> A x      arg : T
-------------------------------------app-Intro
Γ ⊢ₛ f arg : A arg
``` -/
| app : Tmₛ Γ (SPi T A) -> (arg : T) -> Tmₛ Γ (A arg)

-- -- ! This fails:
-- gen_injective_theorems% Tmₛ

/-- Constructor types `... -> Self ...`.

Example `"(n : Nat) -> A -> Vec n -> Vec (n + 1)"`:
```
def V_cons (A : Type) : Tyₚ Vₛ :=
  PPi Nat fun n => -- (n : Nat) ->
    PPi A fun _ => -- A ->
      PFunc ((Tmₛ.var vz) @ n) <| -- Vec n ->
        El ((Tmₛ.var vz) @ (n + 1)) -- Vec (n + 1)
```

The only way to create a `Tyₚ` is by ending it with a `El`, which must be a term in the universe `U`.
The only way to create a term like that is by using `Tmₛ.app` and `Tmₛ.var`.
For example the variables are `Even` and `Odd`, i.e. the other types in the mutual block being defined,
then `Even @ 123` is a term in universe `U`. -/
inductive Tyₚ : Conₛ -> Type (u+1)
| El : Tmₛ Γₛ U -> Tyₚ Γₛ
| PPi   : (T : Type u) -> (T -> Tyₚ Γₛ) -> Tyₚ Γₛ
| PFunc : Tmₛ Γₛ U   ->       Tyₚ Γₛ  -> Tyₚ Γₛ
-- | PInf -- https://arxiv.org/pdf/2006.11736.pdf search for "infinitary" (page 5).
open Tyₚ

/-- List of constructor descriptions.

Example (natural numbers):
```
El (.var .vz) :: PFunc (.var .vz) (El (.var .vz)) :: []
```
Example (vectors):
```
V_cons ▹ V_nil A :: []
``` -/
inductive Conₚ : Conₛ -> Type (u+1)
| nil : Conₚ Γ
| ext :  Conₚ Γ -> Tyₚ Γ -> Conₚ Γ
notation "⬝" => Conₚ.nil
infixl:40 " ▹ " => Conₚ.ext
-- infixl:40 " ▹ₚ " => Conₚ.ext

section Examples
  /-- Corresponds to `Nat : U`. -/
  def Nₛ : Conₛ := ⬝ ▹ U
  /-- Corresponds to the two constructors `Nat.zero : Nat` and `Nat.succ : Nat -> Nat`. -/
  def N  : Conₚ Nₛ := (⬝ ▹ El (.var .vz)) ▹ PFunc (.var .vz) (El (.var .vz))

  -- Vec : Nat -> U
  def Vₛ : Conₛ.{0} := ⬝ ▹ SPi Nat (fun _ => U)

  -- Vec : Nat -> U   ⊢ₛ   Vec 0 : U
  def V_nil : Tyₚ Vₛ := El (.app (.var .vz) 0) -- Vec 0

  -- Vec : Nat -> U   ⊢ₛ   (n : Nat) -> A -> Vec n -> Vec (n + 1)
  def V_cons {A : Type} : Tyₚ Vₛ :=
    PPi Nat fun n => -- (n : Nat) ->
      PPi A fun _ => -- A ->
        PFunc (.app (Tmₛ.var vz) n) <| -- Vec n ->
          El (.app (Tmₛ.var vz) (n + 1)) -- Vec (n + 1)

  def Vₚ (A : Type) : Conₚ Vₛ := (⬝ ▹ V_nil) ▹ @V_cons A
end Examples

-- # Semantics

/-- Interprets a sort type, for example `SPi Nat (fun n => U)` becomes `Nat -> Type`.
  The second `v` universe parameter is not strictly necessary, but it is later used to the same effect as `ULift`. -/
-- @[aesop unsafe]
def TyₛA.{u, v} : Tyₛ.{u} -> Type ((max u v) + 1)
| U => Type (max u v)
| SPi T A => (t : T) -> TyₛA (A t)

/-- Interprets a context of type formers.  The `Vec` example becomes `(Nat -> Type) × Unit`. -/
-- @[aesop unsafe]
def ConₛA.{u, v} : Conₛ.{u} -> Type ((max u v) + 1)
| .nil => PUnit.{(max u v) + 2}
| .ext Γ A => Prod.{(max u v) + 1} (ConₛA Γ) (TyₛA.{u, v} A)

example : ConₛA Vₛ = (PUnit.{2} × (Nat -> Type)) := Eq.refl _

#check And.rec
#check Or.rec


mutual
inductive Even : Nat -> Prop
inductive Odd : Nat -> Prop
end

#check Even.rec
#check Odd.rec

/--
  Variable lookup. Given a context `Γₛ` and an interpretation `γₛ` for that context,
  we find the interpretation that we care about.
  Note that `γₛ` is a "list" with `List.cons` replaced with `Prod.mk`.

  For example if `Γₛ` is `["(n:Nat) -> U"]`, and if `γₛ` is `⟨Vec, ()⟩`,
  then `VarₛA vz γₛ` will reduce to `Vec`.

  This function returns an actual (unquoted) Lean type, e.g. `Vec`.
-/
-- @[aesop unsafe]
def VarₛA : Varₛ Γₛ Aₛ -> ConₛA Γₛ -> TyₛA Aₛ
| vz  , ⟨_, a⟩ => a
| vs v, ⟨γₛ, _⟩ => VarₛA v γₛ

-- Doing it this way somehow results in non-defeq for eqns
def TmₛA_impl.{u} : {Γₛ : Conₛ.{u}} -> {Aₛ : Tyₛ} -> Tmₛ Γₛ Aₛ -> ConₛA.{u, v} Γₛ -> TyₛA.{u, v} Aₛ
| Γ, A, @Tmₛ.var _   _ v  , γₛ => VarₛA v γₛ
| Γ, _, @Tmₛ.app Γ T A t u, γₛ => (TmₛA_impl t γₛ) u

/-- A `Vec` example in pseudocode, where quotation marks refer to object language:
```
@TmₛA ["Nat -> Type"] "Type" "Vec 123" ⟨Vec, ()⟩
```
reduces to:
```
(@TmₛA ["Nat -> Type"] "Type" "Vec" ⟨Vec, ()⟩) 123
```
reduces to:
```
Vec 123
```
The interesting thing here is that the quoted `"Vec"` is purely syntactic and doesn't use
the actual `Vec` at all, it is merely a de-Brujin index into the context, which is entirely nameless.
The purpose of `TmₛA` is to interpret the syntactic `"Vec 123"` into the actual `Vec 123`,
by giving it the actual `Vec` interpretation via the `γₛ : ConₛA Γₛ`

The [original Agda code](https://bitbucket.org/javra/inductive-families/src/717f404c220e17d0ac5917306fd74dd0c4883cde/agda/IFA.agda#lines-16:19)
for `TmₛA` is the following, although it has `VarₛA` inlined, hence 3 cases:
```agda
_ᵃt : ∀{ℓ Γc B} → TmS Γc B → _ᵃc {ℓ} Γc → _ᵃS {ℓ} B
(var vvz ᵃt)     (γ , α) = α
(var (vvs t) ᵃt) (γ , α) = (var t ᵃt) γ
((t $S α) ᵃt)    γ       = (t ᵃt) γ α
```
-/

@[implemented_by TmₛA_impl]
def TmₛA.{u} : {Γₛ : Conₛ.{u}} -> {Aₛ : Tyₛ} -> Tmₛ Γₛ Aₛ -> ConₛA.{u, v} Γₛ -> TyₛA.{u, v} Aₛ
| Γₛ, Aₛ, t, γₛ => @Tmₛ.rec Γₛ (fun Aₛ _ => TyₛA Aₛ)
  (@fun _Aₛ v => VarₛA v γₛ)
  (@fun _ _Aₛ _t u ih => ih u)
  Aₛ t

-- @[simp, aesop unsafe]
theorem TmₛA_var  : TmₛA (Tmₛ.var v) γₛ = VarₛA v γₛ := rfl
-- @[simp, aesop unsafe]
theorem TmₛA_app  : TmₛA (Tmₛ.app t u) γₛ = (TmₛA t γₛ) u := rfl

example {Vec : Nat -> Type} : @TmₛA (⬝ ▹ SPi Nat (fun _ => U)) U (.app (.var .vz) 123) ⟨⟨⟩, Vec⟩ = Vec 123 := rfl

/-- Interprets a constructor type. See below for examples.  Example:
```
TyₚA (V_cons A) ⟨⟨⟩, Vec⟩
```
reduces to the type of `Vec.cons` as you would expect:
```
(n : Nat) -> A -> Vec n -> Vec (n + 1)
``` -/
-- @[aesop unsafe]
def TyₚA.{u, v} : Tyₚ.{u} Γₛ -> ConₛA.{u, v} Γₛ -> Type (max u v)
| El         Self, γₛ => TmₛA Self γₛ
| PPi   T    Rest, γₛ => (arg : T)    -> TyₚA (Rest arg) γₛ
| PFunc Self Rest, γₛ => TmₛA Self γₛ -> TyₚA Rest γₛ

-- def
def test : Tyₚ (⬝ ▹ U) := PPi Unit (fun _ => PPi Nat (fun _ => El (.var .vz)))
#reduce TyₚA test

example {Vec : Nat -> Type} {_A : Type}
  : TyₚA V_nil ⟨⟨⟩, Vec⟩
  = Vec 0
  := rfl

example {Vec : Nat -> Type} {A : Type}
  : TyₚA (@V_cons A) ⟨⟨⟩, Vec⟩
  = ((n : Nat) -> A -> Vec n -> Vec (n + 1))
  := rfl

/-- Interprets a (mutual) inductive type. This is just `TyₚA` for each ctor joined with `×`.
Example:
```
ConₚA (V_cons ▹ V_nil A :: []) ⟨⟨⟩, Vec⟩
```
reduces to the Lean type
```
  (Vec 0) -- `Vec.nil`
× ((n : Nat) -> A -> Vec n -> Vec (n + 1)) -- `Vec.cons`
× Unit
``` -/
-- @[aesop unsafe]
def ConₚA.{u, v} : Conₚ.{u} Γₛ -> ConₛA.{u, v} Γₛ -> Type (max u v)
| ⬝    , _ => PUnit
| Γ ▹ A, γₛ => ConₚA Γ γₛ × TyₚA.{u, v} A γₛ

example {Vec : Nat -> Type} {A : Type}
  : ConₚA (Vₚ A) ⟨⟨⟩, Vec⟩
  = ((Unit × Vec 0) × ((n : Nat) -> A -> Vec n -> Vec (n + 1)))
  := rfl

-- ## Displayed Algebras

/-- Compute motive type.

Example: `TyₛD (SPi Nat (fun _ => U)) Vec` reduces to `(n : Nat) -> Vec n -> Type`. -/
-- @[aesop unsafe]
def TyₛD.{u, v} : (Aₛ : Tyₛ.{u}) -> TyₛA.{u, v} Aₛ -> Type ((max u v) + 1)
| U, T => T -> Type (max u v)
| SPi T Aₛ, f => (t : T) -> TyₛD (Aₛ t) (f t)

/-- Compute motive type for each mutually defined inductive type.

Example:
```
ConₛD Vₛ ⟨⟨⟩, Vec⟩
```
reduces to just one motive type:
```
((t : Nat) → Vec t -> Type) × Unit
``` -/
-- @[aesop unsafe]
def ConₛD.{u, v} : (Γₛ : Conₛ.{u}) -> ConₛA.{u, v} Γₛ -> Type ((max u v) + 1)
| ⬝, _ => PUnit
| Γ ▹ A, ⟨γ, a⟩ => ConₛD Γ γ × TyₛD A a

example {Vec : Nat -> Type} : ConₛD Vₛ ⟨⟨⟩, Vec⟩ = (PUnit.{2} × ((t : Nat) → Vec t -> Type)) := rfl

set_option linter.unusedVariables false in
def VarₛD : {Γₛ : Conₛ} -> {γₛ : ConₛA Γₛ} -> (v : Varₛ Γₛ Aₛ) -> ConₛD Γₛ γₛ -> TyₛD Aₛ (VarₛA v γₛ)
| _ ▹ _, ⟨_, _⟩, .vz  , ⟨_,  a⟩ => a
| _ ▹ _, ⟨_, _⟩, .vs v, ⟨γD, _⟩ => VarₛD v γD

-- def TyₛD_cast_var  : TyₛD Aₛ (VarₛA v γₛ) -> TyₛD Aₛ (TmₛA (Tmₛ.var v) γₛ) := TmₛA_var ▸ id
-- def TyₛD_cast_var' : TyₛD Aₛ (TmₛA (Tmₛ.var v) γₛ) -> TyₛD Aₛ (VarₛA v γₛ) := TmₛA_var ▸ id
-- def TyₛD_cast_app  {Aₛ : T → Tyₛ} {t : Tmₛ Γₛ (SPi T Aₛ)} : TyₛD (Aₛ u) (TmₛA t γₛ u) -> TyₛD (Aₛ u) (TmₛA (Tmₛ.app t u) γₛ) := TmₛA_app ▸ id
-- def TyₛD_cast_app' {Aₛ : T → Tyₛ} {t : Tmₛ Γₛ (SPi T Aₛ)} : TyₛD (Aₛ u) (TmₛA (Tmₛ.app t u) γₛ) -> TyₛD (Aₛ u) (TmₛA t γₛ u) := TmₛA_app ▸ id

-- theorem TyₛD_cast_cancel : @TyₛD_cast_var Aₛ Γₛ v γₛ ∘ TyₛD_cast_var' = id := by
--   unfold Function.comp
--   unfold TyₛD_cast_var TyₛD_cast_var'
--   -- rw [TyₛD_cast_var, TyₛD_cast_var']
--   sorry
--   done

def TmₛD_impl : {Γₛ : Conₛ} -> {Aₛ : Tyₛ} -> {γₛ : ConₛA Γₛ} -> (t : Tmₛ Γₛ Aₛ) -> ConₛD Γₛ γₛ -> TyₛD Aₛ (TmₛA t γₛ)
| _, _, γₛ, .var v                    , γₛD => VarₛD v γₛD
| _, _, γₛ, .app (T := T) (A := A) t u, γₛD => TmₛD_impl t γₛD u

/--
The [original Agda code](https://bitbucket.org/javra/inductive-families/src/717f404c220e17d0ac5917306fd74dd0c4883cde/agda/IFD.agda#lines-17:20)
for this is, again with `VarₛD` inlined:
```agda
ᵈt : ∀{ℓ' ℓ Γc B}(t : TmS Γc B){γc : _ᵃc {ℓ} Γc} → ᵈc {ℓ'} Γc γc → ᵈS {ℓ'} B ((t ᵃt) γc)
ᵈt (var vvz)     (γcᵈ , αᵈ) = αᵈ
ᵈt (var (vvs t)) (γcᵈ , αᵈ) = ᵈt (var t) γcᵈ
ᵈt (t $S α)      γcᵈ        = ᵈt t γcᵈ α
``` -/
-- ! TmₛD needs casts because reduction behaviour of TmₛA is broken.
-- And for some reason TmₚD works just fine? What...
-- @[aesop unsafe]
@[implemented_by TmₛD_impl]
def TmₛD : {Γₛ : Conₛ} -> {Aₛ : Tyₛ} -> {γₛ : ConₛA Γₛ} -> (t : Tmₛ Γₛ Aₛ) -> ConₛD Γₛ γₛ -> TyₛD Aₛ (TmₛA t γₛ)
| Γₛ, Aₛ, γₛ, t, γₛD => @Tmₛ.rec Γₛ (fun Aₛ t => TyₛD Aₛ (TmₛA t γₛ))
  (@fun _Aₛ v => VarₛD v γₛD)
  (@fun _ _Aₛ _t u ih => ih u)
  Aₛ t


theorem TmₛD_var : TmₛD (Tmₛ.var v) γₛD = VarₛD v γₛD := by rfl
theorem TmₛD_app : TmₛD (.app t u)  γₛD = TmₛD t γₛD u := by rfl

/-- Example:
```
@TyₚD Vₛ ⟨⟨⟩, Vec A⟩ V_nil ⟨⟨⟩, P⟩ Vec.nil
  = P 0 Vec.nil
```
Example:
```
@TyₚD Vₛ ⟨⟨⟩, Vec A⟩ V_cons ⟨⟨⟩, P⟩ Vec.cons
  = ((n : Nat) -> (a : A) -> (v : Vec A n) -> P n v -> P (n + 1) (Vec.cons n a v))
``` -/
-- Note: The `Self` here can be a little misleading, as it may be a nested type with different indices.
def TyₚD.{u, v} : (A : Tyₚ.{u} Γₛ) -> ConₛD.{u} Γₛ γₛ -> TyₚA.{u, v} A γₛ -> Type (max u v)
| El         Self, γD, self =>                                               TmₛD Self γD self
| PPi   T    Rest, γD, f    => (t : T) ->                                    TyₚD (Rest t) γD (f t)
| PFunc Self Rest, γD, f    => ⦃self : TmₛA Self γₛ⦄ -> TmₛD Self γD self -> TyₚD Rest γD (f self)

inductive Vec (A : Type u) : Nat -> Type u
| nil : Vec A 0
| cons : (n : Nat) -> A -> Vec A n -> Vec A (n + 1)

example {A : Type} {P : (n : Nat) -> Vec A n -> Type}
  : @TyₚD Vₛ ⟨⟨⟩, Vec A⟩ V_nil ⟨⟨⟩, P⟩ Vec.nil
  = P 0 Vec.nil
  := rfl
example {A : Type} {P : (n : Nat) -> Vec A n -> Type}
  : @TyₚD Vₛ ⟨⟨⟩, Vec A⟩ V_cons ⟨⟨⟩, P⟩ Vec.cons
  = ((n : Nat) -> (a : A) -> (v : Vec A n) -> P n v -> P (n + 1) (Vec.cons n a v))
  := rfl

/-- Example:
```
@ConₚD Vₛ ⟨⟨⟩, Vec A⟩ (V_cons ▹ V_nil :: []) ⟨⟨⟩, P⟩ ⟨Vec.nil, Vec.cons, ⟨⟩⟩
```
reduces to
```
  P 0 Vec.nil
× ((n : Nat) -> (a : A) -> (v : Vec A n) -> P n v -> P (n + 1) (Vec.cons n a v))
× PUnit
``` -/
def ConₚD.{u, v} : (Γ : Conₚ.{u} Γₛ) -> ConₛD.{u, v} Γₛ γₛ -> ConₚA.{u, v} Γ γₛ -> Type (max u v)
| ⬝, _, _ => PUnit
| Γ ▹ A, γD, ⟨γ, a⟩ => ConₚD Γ γD γ × TyₚD A γD a

example {P : (n : Nat) -> Vec A n -> Type}
  : @ConₚD Vₛ ⟨⟨⟩, Vec A⟩ ((⬝ ▹ V_nil) ▹ V_cons) ⟨⟨⟩, P⟩ ⟨⟨⟨⟩, Vec.nil⟩, Vec.cons⟩
  = (
      (Unit
      × (P 0 Vec.nil))
      × ((n : Nat) -> (a : A) -> (v : Vec A n) -> P n v -> P (n + 1) (Vec.cons n a v))
    )
  := rfl

#check Vec.rec /-
  {A : Type} →
  {motive : (a : Nat) → Vec A a → Sort u} →
  (case_nil : motive 0 Vec.nil) →
  (case_cons : (n : Nat) → (a : A) → (v : Vec A n) → motive n v → motive (n + 1) (Vec.cons n a v)) →
  {a : Nat} →
  (t : Vec A a) →
  motive a t
-/


-- ## Sections

/-- Example:
```
TyₛS (SPi Nat (fun _ => U)) (Vec A) (fun _ _ => R)
```
reduces to
```
(n : Nat) -> (v : Vec A n) -> R
``` -/
def TyₛS.{u, v} : (Aₛ : Tyₛ.{u}) -> (αₛ : TyₛA.{u, v} Aₛ) -> TyₛD.{u, v} Aₛ αₛ -> Type (max u v)
| U       , T , TD  => (t : T) -> TD t
| SPi T Aₛ, fₛ, fₛd => (t : T) -> TyₛS (Aₛ t) (fₛ t) (fₛd t)

example {A R} : TyₛS (SPi Nat (fun _ => U)) (Vec A) (fun _ _ => R) = ((n : Nat) -> (v : Vec A n) -> R) := rfl

/-- Example:
```
ConₛS Vₛ ⟨⟨⟩, Vec A⟩ ⟨fun (n : Nat) (v : Vec A n) => R, ⟨⟩⟩
```
reduces to
```
  ((n : Nat) -> (v : Vec A n) -> R)
× PUnit
``` -/
def ConₛS.{u, v} : (Γₛ : Conₛ.{u}) -> (γₛ : ConₛA.{u, v} Γₛ) -> ConₛD.{u, v} Γₛ γₛ -> Type (max u v)
| ⬝, ⟨⟩, ⟨⟩ => PUnit
| Γₛ ▹ Aₛ, ⟨γₛ, αₛ⟩, ⟨γₛd, αₛd⟩ => ConₛS Γₛ γₛ γₛd × TyₛS Aₛ αₛ αₛd

example {A R} : ConₛS Vₛ ⟨⟨⟩, Vec A⟩ ⟨⟨⟩, fun _n _v => R⟩ = (Unit × ((n : Nat) -> (v : Vec A n) -> R)) := rfl

set_option linter.unusedVariables false in
def VarₛS : {Γₛ : Conₛ} -> {γₛ : ConₛA Γₛ} -> {γD : ConₛD Γₛ γₛ} -> (x : Varₛ Γₛ Aₛ) -> ConₛS Γₛ γₛ γD -> TyₛS Aₛ (VarₛA x γₛ) (VarₛD x γD)
| _ ▹ _, ⟨_,_⟩, ⟨_,_⟩, .vz  , ⟨γₛS, αₛS⟩ => αₛS
| _ ▹ _, ⟨_,_⟩, ⟨_,_⟩, .vs v, ⟨γₛS, αₛS⟩ => VarₛS v γₛS

-- https://leanprover.zulipchat.com/#narrow/stream/270676-lean4/topic/rw.20term.20depended.20on.20by.20other.20argument/near/409268800
theorem TyₛS_helper {Aₛ : Tyₛ} {a b : TyₛA Aₛ} (hA : a = b) (d : TyₛD Aₛ a)
  : TyₛS Aₛ a d = TyₛS Aₛ b (hA ▸ d) -- TyₛD Aₛ a -> TyₛD Aₛ b
  := by subst hA; rfl


theorem ConₛS_helper {Γₛ : Conₛ} {γₛ γₛ' : ConₛA Γₛ} (hA : γₛ = γₛ') (dₛ : ConₛD Γₛ γₛ)
  : ConₛS Γₛ γₛ dₛ = ConₛS Γₛ γₛ' (hA ▸ dₛ)
  := by subst hA; rfl

def TmₛS : {Γₛ : Conₛ} -> {Aₛ : Tyₛ} -> {γₛ : ConₛA Γₛ} -> {γₛD : ConₛD Γₛ γₛ} ->
  (t : Tmₛ Γₛ Aₛ) -> ConₛS Γₛ γₛ γₛD -> TyₛS Aₛ (TmₛA t γₛ) (TmₛD t γₛD)
| Γₛ, Aₛ, γₛ, γₛD, .var v, γₛS => VarₛS v γₛS
| Γₛ, _, γₛ, γₛD, .app (T := T) (A := Aₛ) t u, γₛS => TmₛS t γₛS u

/-- Computation rule. -/
def TyₚS : (A : Tyₚ Γₛ) -> ConₛS Γₛ γₛ γₛD -> (α : TyₚA A γₛ) -> TyₚD A γₛD α -> Prop
| El         Self, γₛS, α, αD =>                          TmₛS Self γₛS α = αD -- note the equality here
| PPi   T    Rest, γₛS, f, fD => (t    : T)            -> TyₚS (Rest t) γₛS (f t)    (fD t)
| PFunc Self Rest, γₛS, f, fD => (self : TmₛA Self γₛ) ->
  -- fD : {self : TmₛA Self γₛ} → TmₛD Self γD self → TyₚD Rest γD (f self)
  TyₚS  Rest    γₛS (f self) (@fD self (TmₛS Self γₛS self))

/-- Computation rules for all constructors. -/
def ConₚS : (Γ : Conₚ Γₛ) -> ConₛS Γₛ γₛ γₛD -> (γ : ConₚA Γ γₛ) -> ConₚD Γ γₛD γ -> Prop
| ⬝    ,   _,     ⟨⟩,       ⟨⟩ => True
| Γ ▹ A, γₛS, ⟨γ, α⟩, ⟨γD, αD⟩ => ConₚS Γ γₛS γ γD ∧ TyₚS A γₛS α αD

/-- Computation rules for Vec. This computes the *statement*, but doesn't *prove* it yet. -/
example : @ConₚS Vₛ ⟨⟨⟩, Vec A⟩ ⟨⟨⟩, Q⟩ (Vₚ A) ⟨⟨⟩, elim⟩ ⟨⟨⟨⟩, Vec.nil⟩, Vec.cons⟩ ⟨⟨⟨⟩, nilD⟩, consD⟩
  = ((
      True
    ∧ (elim 0 Vec.nil = nilD))
    ∧ ((n : Nat) -> (a : A) -> (v : Vec A n) -> (elim (n + 1) (Vec.cons n a v) = consD n a (elim n v)))
  )
  := rfl

-- # Substitutions

inductive Subₛ : (Γₛ : Conₛ) -> (Δₛ : Conₛ) -> Type (u+1)
| nil : Subₛ Γₛ ⬝
| cons : Subₛ Γₛ Δₛ -> Tmₛ Γₛ Aₛ -> Subₛ Γₛ (Δₛ ▹ Aₛ)

/-- Substitutes a variable `v ∈ Δₛ` with a Γₛ-term. -/
-- @[aesop unsafe]
def SubₛVar : Varₛ Δₛ Aₛ -> Subₛ Γₛ Δₛ -> Tmₛ Γₛ Aₛ
| .vz  , .cons _ t => t
| .vs v, .cons σ _ => SubₛVar v σ

example : SubₛVar .vz (.cons σ t) = t := rfl
example : SubₛVar (.vs v) (.cons σ t) = SubₛVar v σ := rfl

/-- Applies the substitution to a term, resulting in a new term in the new context. -/
-- @[aesop unsafe]
def SubₛTm : {Aₛ : _} -> Tmₛ Δₛ Aₛ -> Subₛ Γₛ Δₛ -> Tmₛ Γₛ Aₛ
| _, .var v, σ => SubₛVar v σ
| _, .app (A := _A) t u, σ => .app (SubₛTm t σ) u

-- @[aesop unsafe]
theorem SubₛTm_var : SubₛTm (Tmₛ.var v) σ = (SubₛVar v σ) := rfl
theorem SubₛTm_app : SubₛTm (Tmₛ.app t u) σ = .app (SubₛTm t σ) u := rfl

/-- Point types are valid in a given sort context. Given a substitution between sort contexts,
  changes the point type's underlying sort context. -/
def SubₛTy : Tyₚ Δₛ -> Subₛ Γₛ Δₛ -> Tyₚ Γₛ
| El Self, σ => El (SubₛTm Self σ)
| PPi T Rest, σ => PPi T (fun t => SubₛTy (Rest t) σ)
| PFunc Self Rest, σ => PFunc (SubₛTm Self σ) (SubₛTy Rest σ)

def SubₛCon : Conₚ Δₛ -> Subₛ Γₛ Δₛ -> Conₚ Γₛ
| ⬝, _ => ⬝
| Γ ▹ A, σ => SubₛCon Γ σ ▹ SubₛTy A σ

/-- Increment all de brujin indices in this term by one. -/
-- @[aesop unsafe]
def vshift : {Aₛ : Tyₛ} -> Tmₛ Γₛ Aₛ -> Tmₛ (Γₛ ▹ Bₛ) Aₛ
| _, .var v => .var (.vs v)
| _, .app (A := _A) t u => .app (vshift t) u

def weaken_impl.{u} : {Γₛ Δₛ : Conₛ.{u}} -> {Aₛ : Tyₛ.{u}} -> Subₛ.{u} Γₛ Δₛ -> Subₛ (Γₛ ▹ Aₛ) Δₛ
| Γₛ, .nil    , Aₛ, .nil => .nil
| Γₛ, Δₛ ▹ Bₛ, Aₛ, .cons σ t => Subₛ.cons (weaken_impl σ) (vshift t)

-- /-- Weakens a substitution.
-- -- @[aesop unsafe]
--   Given a substitution `σ` which replaces all variables `Δₛ ⊢ v` with terms `Γₛ ⊢ t`,
--   the weakened substitution will replace all variables `Δₛ ⊢ v` with terms `Γₛ, Aₛ ⊢ t`.
--   The stored terms thus need to be shifted using `vshift`. -/
-- example : @weaken'  Γₛ .nil Aₛ .nil = .nil := rfl
-- example : @weaken'  Γₛ (Δₛ ▹ Bₛ) Aₛ (.cons σ t) = Subₛ.cons (weaken' σ) (vshift t) := by rw [weaken'] -- doesn't work by rfl

@[implemented_by weaken_impl]
def weaken.{u} {Γₛ Δₛ : Conₛ.{u}} {Aₛ : Tyₛ.{u}} (σ : Subₛ.{u} Γₛ Δₛ) : Subₛ (Γₛ ▹ Aₛ) Δₛ
  := @Subₛ.rec Γₛ (fun Δₛ _ => Subₛ (Γₛ ▹ Aₛ) Δₛ)
    (Subₛ.nil)
    (@fun _ _ _ t σ_ih => Subₛ.cons σ_ih (vshift t))
    _ σ

theorem weaken_nil  : @weaken Γₛ .nil Aₛ .nil = .nil := rfl
theorem weaken_cons : @weaken Γₛ (Δₛ ▹ Bₛ) Aₛ (.cons σ t) = Subₛ.cons (weaken σ) (vshift t) := rfl

/-- Identity substitution. Does nothing (replaces all variables by itself). -/
-- @[aesop unsafe]
def Subₛ.id : (Γₛ : Conₛ) -> Subₛ Γₛ Γₛ
| ⬝ => .nil
| Γₛ ▹ _ => .cons (weaken (Subₛ.id Γₛ)) (.var .vz)

theorem Subₛ.id_nil : Subₛ.id .nil = .nil := rfl
theorem Subₛ.id_ext : Subₛ.id (Γₛ ▹ Aₛ) = .cons (weaken (Subₛ.id Γₛ)) (.var .vz) := rfl

def Subₛ.comp : Subₛ Θₛ Δₛ -> Subₛ Γₛ Θₛ -> Subₛ Γₛ Δₛ
| .nil, δ => .nil
| .cons σ s, δ => .cons (Subₛ.comp σ δ) (SubₛTm s δ)

-- Substitution projection are just pattern matching `let .cons δ t := σ`

def SubₛA : Subₛ Γₛ Δₛ -> ConₛA Γₛ -> ConₛA Δₛ
| .nil     ,  _ => ⟨⟩
| .cons σ t, γₛ => ⟨SubₛA σ γₛ, TmₛA t γₛ⟩

theorem SubₛA_nil : SubₛA .nil γₛ = ⟨⟩ := rfl
theorem SubₛA_cons : SubₛA (.cons σ t) γₛ = ⟨SubₛA σ γₛ, TmₛA t γₛ⟩ := rfl

def SubₛD : (σ : Subₛ Γₛ Δₛ) -> ConₛD Γₛ γₛ -> ConₛD Δₛ (SubₛA σ γₛ)
| .nil, γₛD => ⟨⟩
| .cons σ t, γₛD => ⟨SubₛD σ γₛD, TmₛD t γₛD⟩

def SubₛS : (σ : Subₛ Γₛ Δₛ) -> ConₛS Γₛ γₛ γₛD -> ConₛS Δₛ (SubₛA σ γₛ) (SubₛD σ γₛD)
| .nil, γₛD => ⟨⟩
| .cons σ t, γₛD => ⟨SubₛS σ γₛD, TmₛS t γₛD⟩

/-- It is impossible to have a term in an empty context. -/
-- @[aesop safe]
theorem Tmₛ_emptyCtx (t : Tmₛ ⬝ A) : False := by
induction t with
| var v => cases v
| app _ _ ih => exact ih

-- @[aesop safe]
theorem Subₛ_emptyCtx : Subₛ ⬝ (⬝ ▹ A) -> False
| .cons _ t => Tmₛ_emptyCtx t

namespace Examples -- Substitutions
  /-- Substitution from nothing to nothing is okay. -/
  example : Subₛ ⬝ ⬝ := .nil
  /-- Can't have a substitution from nothing to something. -/
  example : Subₛ ⬝ (⬝ ▹ .U) -> False := by intro σ; let .cons _ t := σ; exact Tmₛ_emptyCtx t
  /-- Can have a substitution from something to nothing. -/
  example : Subₛ (⬝ ▹ .U) ⬝ := .nil
  /-- Map every var to itself. -/
  example : Subₛ (⬝ ▹ .U) (⬝ ▹ .U) := .cons .nil (.var .vz)

  def σ : Subₛ Vₛ Vₛ := .cons .nil (.var .vz) -- remember sort ctor, so just one entry in ctx.
  def σ_Vec2List : Subₛ Vₛ (⬝ ▹ U) := .cons .nil (.app (.var .vz) 123) -- remember sort ctor, so just one entry in ctx.
  example : SubₛA (Γₛ := Vₛ) σ_Vec2List ⟨⟨⟩, Vec String⟩ = ⟨⟨⟩, Vec String 123⟩ := rfl

  #check SubₛTm
  #reduce SubₛTm (Δₛ := (⬝ ▹ U)) (Γₛ := Vₛ) (.var .vz) σ_Vec2List
end Examples


/- ### Lemma 12 -/

-- @[aesop unsafe]
theorem VarₛA_Subₛ {σ : Subₛ Γₛ Δₛ} {v : Varₛ Δₛ Aₛ} : TmₛA (SubₛVar v σ) γₛ = VarₛA v (SubₛA σ γₛ) := by
  induction v with
  | vz => let .cons σ t := σ; rfl
  | vs v ih => let .cons σ _ := σ; exact ih

-- @[aesop unsafe]
theorem TmₛA_Subₛ {σ : Subₛ Γₛ Δₛ} {t : Tmₛ Δₛ Aₛ} : TmₛA (SubₛTm t σ) γₛ = TmₛA t (SubₛA σ γₛ) := by
  induction t with
  | var v => rw [TmₛA]; exact VarₛA_Subₛ
  | app t u ih => simp_all only [SubₛTm, TmₛA_app]

-- @[aesop unsafe]
theorem TyₚA_Subₛ {σ : Subₛ Γₛ Δₛ} : TyₚA.{u, v} (SubₛTy A σ) γₛ = TyₚA.{u, v} A (SubₛA σ γₛ) := by
  induction A with
  | El Self =>
    exact TmₛA_Subₛ
  | PPi T Rest ih =>
    simp only [TyₚA]
    apply @forall_pcongr T (fun a => TyₚA (SubₛTy (Rest a) σ) γₛ) (fun a => TyₚA (Rest a) (SubₛA σ γₛ))
    exact ih
  | PFunc Self Rest ih =>
    simp only [TyₚA]
    rw [TmₛA_Subₛ, ih]

@[simp]
theorem TmₛA_shift : TmₛA (vshift t) (γₛ, aₛ) = TmₛA t γₛ := by
  induction t with
  | var v => simp only [vshift]; rfl
  | app t u ih => simp only [vshift, TmₛA_app]; rw [ih]

@[simp]
theorem SubₛA_weaken (σ : Subₛ Γₛ Δₛ) : SubₛA (weaken σ) (γₛ, aₛ) = SubₛA σ γₛ := by
  induction σ with
  | nil => rfl
  | cons σ t ih =>
    rw [weaken_cons, SubₛA, SubₛA]
    rw [ih, TmₛA_shift]

@[simp]
theorem SubₛA_id : SubₛA (Subₛ.id Γₛ) γₛ = γₛ := by
  induction Γₛ with
  | nil => rfl
  | ext Γₛ Aₛ ih =>
    let ⟨γₛ, aₛ⟩ := γₛ
    simp only [Subₛ.id, SubₛA, TmₛA, VarₛA, SubₛA_weaken, ih]

-- def Subₛ_id_cast : SubₛA (Subₛ.id Γₛ) γₛ -> γₛ := fun

-- Now the same stuff, but for -D instead of -A

-- def TyₛD_cast_var : TyₛD Aₛ (TmₛA (SubₛVar v σ) γₛ) -> TyₛD Aₛ (VarₛA v (SubₛA σ γₛ)) := VarₛA_Subₛ ▸ id
-- def TyₛD_cast_tm  : TyₛD Aₛ (TmₛA (SubₛTm t σ) γₛ) -> TyₛD Aₛ (TmₛA t (SubₛA σ γₛ)) := TmₛA_Subₛ ▸ id
def TyₛD_cast_var : TyₛD Aₛ (TmₛA (SubₛVar v σ) γₛ) -> TyₛD Aₛ (VarₛA v (SubₛA σ γₛ)) := fun x => VarₛA_Subₛ ▸ x
def TyₛD_cast_tm  : TyₛD Aₛ (TmₛA (SubₛTm t σ) γₛ) -> TyₛD Aₛ (TmₛA t (SubₛA σ γₛ)) := fun x => TmₛA_Subₛ ▸ x

-- example {t : Tmₛ Γₛ (SPi X Aₛ)} : TyₛD_cast_tm (TmₛD (SubₛTm t σ) γₛD) u = TyₛD_cast_tm (TmₛD (SubₛTm t σ) γₛD u) := sorry

-- @[aesop unsafe]
theorem VarₛD_Subₛ {σ : Subₛ Γₛ Δₛ} {v : Varₛ Δₛ Aₛ} : VarₛD v (SubₛD σ γₛ) = TyₛD_cast_var (TmₛD (SubₛVar v σ) γₛ) := by
  induction v with
  | vz => let .cons σ t := σ; rfl
  | vs v ih => let .cons σ _ := σ; apply ih

-- @[aesop unsafe]
theorem TmₛD_Subₛ {σ : Subₛ Γₛ Δₛ} {t : Tmₛ Δₛ Aₛ} {γₛ : ConₛA Γₛ} {γₛD : ConₛD Γₛ γₛ}
  : TmₛD t (SubₛD σ γₛD) = TyₛD_cast_tm (TmₛD (γₛ := γₛ) (SubₛTm t σ) γₛD) := by
  induction t with
  | @var Bₛ v =>
    rw [TmₛD_var]
    conv => rhs; simp only [SubₛTm]
    rw [VarₛD_Subₛ, TyₛD_cast_var, TyₛD_cast_tm]
  | @app T Aₛ t u ih =>
    rw [TmₛD_app]
    have ih := Eq.cast_apply_u
      (h := Eq.symm <| @TmₛA_Subₛ Γₛ Δₛ (SPi T Aₛ) γₛ σ t)
      (hu := fun u => Eq.symm <| Eq.apply_u (@TmₛA_Subₛ Γₛ Δₛ (SPi T Aₛ) γₛ σ t) u)
      ih
      u
    rw [ih]
    conv => rhs; simp only [SubₛTm]
    rw [TmₛD_app]
    simp [TyₛD_cast_tm]
    done

-- @[aesop unsafe]
theorem TmₛD_shift {γₛ : ConₛA Γₛ} {aₛ : TyₛA Aₛ} {γₛD : ConₛD Γₛ γₛ} {aₛD : TyₛD Aₛ aₛ}
  : TmₛD (Γₛ := Γₛ ▹ Aₛ) (γₛ := ⟨γₛ, aₛ⟩) (vshift t) (γₛD, aₛD) = TmₛA_shift.symm ▸ TmₛD t γₛD
  := by induction t with
    | var v => simp only [vshift, TmₛD, VarₛD]
    | @app T Bₛ t u ih =>
      simp only [vshift, TmₛD_app]
      have ih' := Eq.cast_apply_u
        (h := @TmₛA_shift Γₛ (SPi T Bₛ) t γₛ Aₛ aₛ)
        (hu := Eq.apply_u <| @TmₛA_shift Γₛ (SPi T Bₛ) t γₛ Aₛ aₛ)
        ih
        u
      rw [ih']

theorem ConₛD_cast_pull_eq
  {γₛ1 γₛ2 : ConₛA Γₛ} (ha : γₛ1 = γₛ2)
  {aₛ1 aₛ2 : TyₛA Bₛ} (hb : aₛ1 = aₛ2)
  : (ConₛD Γₛ γₛ1 × TyₛD Bₛ aₛ1) = (ConₛD Γₛ γₛ2 × TyₛD Bₛ aₛ2)
  := by cases ha; cases hb; rfl

theorem ConₛD_cast_pull
  {γₛ1 γₛ2 : ConₛA Γₛ} (ha : γₛ1 = γₛ2)
  {aₛ1 aₛ2 : TyₛA Bₛ} (hb : aₛ1 = aₛ2)
  {γₛD : ConₛD Γₛ γₛ1} {aₛD : TyₛD Bₛ aₛ1}
  : (ha ▸ γₛD, hb ▸ aₛD)
    = (ConₛD_cast_pull_eq ha hb ▸ ⟨γₛD, aₛD⟩ : ConₛD Γₛ γₛ2 × TyₛD Bₛ aₛ2)
  := by cases ha; cases hb; rfl

theorem promote_ConₛA_ConₛD_eq
  (hA : @Eq (ConₛA Γₛ)           a₁     a₂ )
  : @Eq (Sort _) (ConₛD Γₛ a₁) (ConₛD Γₛ a₂)
  := by cases hA; rfl

theorem promote_ConₛA_ConₛD {a₁ a₂ : ConₛA Γₛ} {z : ConₛD Γₛ a₁}
  (hA : @Eq (ConₛA Γₛ)           a₁     a₂ )
  : @Eq (ConₛD Γₛ a₂) (hA ▸ z) ((promote_ConₛA_ConₛD_eq hA) ▸ z)
  := by cases hA; rfl

theorem SubₛD_weaken {σ : Subₛ Γₛ Δₛ} {γₛD : ConₛD Γₛ γₛ}
  : (SubₛD (Γₛ := Γₛ ▹ Aₛ) (γₛ := ⟨γₛ, aₛ⟩) (weaken σ) ⟨γₛD, aₛD⟩) = SubₛA_weaken σ ▸ (SubₛD σ γₛD)
  := by induction σ with
  | nil => rfl
  | @cons Δₛ Bₛ σ t ih =>
    simp only [weaken_cons]
    rw [SubₛD, ih, TmₛD_shift, SubₛD]
    rw [ConₛD_cast_pull]
    rw [promote_ConₛA_ConₛD]

theorem SubₛD_id {γₛD : ConₛD Γₛ γₛ} : SubₛD (Subₛ.id Γₛ) γₛD = SubₛA_id ▸ γₛD := by
  induction Γₛ with
  | nil => rfl
  | ext Γₛ Aₛ ih =>
    let ⟨γₛ, aₛ⟩ := γₛ
    let ⟨γₛD, aₛD⟩ := γₛD
    simp only [Subₛ.id, SubₛD, Subₛ.id]
    rw [TmₛD_var, VarₛD]
    rw [SubₛD_weaken]
    rw [@ih]
    -- generalize (γₛD, aₛD) = z
    -- change ConₛD (Γₛ ▹ Aₛ) (γₛ, aₛ) at z
    -- rw [promote_ConₛA_ConₛD]
    -- rw [promote_ConₛA_ConₛD]
    simp only [ConₛD_cast_pull _ (Eq.refl _)]
    simp only [eq_cast_trans]
    -- Need to show that these two have the same type. Need to promote the rhs cast
    -- lhs cast ::: (ConₛD Γₛ γₛ × TyₛD Aₛ aₛ) = (ConₛD Γₛ (SubₛA (weaken (Subₛ.id Γₛ)) (γₛ, aₛ)) × TyₛD Aₛ aₛ)
    -- Eq.symm SubₛA_id ::: (γₛ, aₛ) = SubₛA (Subₛ.id (Γₛ ▹ Aₛ)) (γₛ, aₛ)
    generalize (γₛD, aₛD) = zD
    change ConₛD (Γₛ ▹ Aₛ) (γₛ, aₛ) at zD
    -- have : (γₛ, aₛ) = SubₛA (Subₛ.id (Γₛ ▹ Aₛ)) (γₛ, aₛ) := sorry
    -- have := promote_ConₛA_ConₛD (z := z)
    -- have
    --   (hA : (γₛ, aₛ) = SubₛA (Subₛ.id (Γₛ ▹ Aₛ)) (γₛ, aₛ))
    --   : hA ▸ zD = promote_ConₛA_ConₛD_eq (a₁ := (γₛ, aₛ)) (a₂ := SubₛA (Subₛ.id (Γₛ ▹ Aₛ)) (γₛ, aₛ)) hA ▸ zD
    --   := sorry
    -- conv => rhs; rw [promote_ConₛA_ConₛD]

    -- have := @ConₛD_cast_pull Γₛ ((@SubₛA_id Γₛ γₛ).symm ▸ γₛD)
    sorry

-- #exit

-- theorem foob : (Γₛ : Conₛ) -> (σ : Subₛ Γₛ Γₛ) -> (v : Varₛ Γₛ Aₛ) -> vshift (SubₛVar v σ) = SubₛVar v (weaken (Aₛ := Bₛ) σ) := by
--   intro Γₛ σ v
--   induction v with
--   | vz =>
--     let .cons σ s := σ
--     simp [SubₛVar, vshift, weaken]
--   | vs v ih =>
--     let .cons σ s := σ
--     simp [SubₛVar, vshift, weaken]
--     exact ih (σ)
--     sorry

-- theorem foob : {Γₛ : Conₛ} -> (v : Varₛ Γₛ Aₛ) -> SubₛVar v (weaken (Aₛ := Bₛ) (Subₛ.id Γₛ)) = vshift (SubₛVar v (Subₛ.id Γₛ))
-- | Γₛ ▹ Bₛ, .vz => by simp [Subₛ.id, SubₛVar, vshift, weaken]
-- | Γₛ ▹ Bₛ, .vs v => by
--   have ih := foob (Bₛ := Bₛ) v
--   have ih₂ := foob (Bₛ := Aₛ) v
--   simp [SubₛVar]
--   -- rw [Subₛ.id]
--   rw [weaken]
--   -- simp [Subₛ.id, SubₛVar, vshift, weaken]
--   sorry

-- theorem foot : (Γₛ : Conₛ) -> (σ : Subₛ Γₛ Γₛ) -> (t : Tmₛ Γₛ Aₛ) -> vshift (SubₛTm t σ) = SubₛTm t (weaken (Aₛ := Bₛ) σ)
-- | Γₛ ▹  _, .cons σ s, .var .vz => by simp [SubₛTm, SubₛVar, vshift, weaken]
-- | Γₛ ▹ Bₛ, .cons σ s, .var (.vs v) => by
--   -- let v' := SubₛVar v σ
--   have : sizeOf (SubₛVar v σ) < sizeOf (Tmₛ.var (.vs v) : Tmₛ (Γₛ ▹ Bₛ) Aₛ) := sorry
--   have ih := foot _ (Bₛ := Bₛ) (.cons σ s) (SubₛVar v σ)
--   simp [SubₛTm, SubₛVar, vshift, weaken]
--   simp [SubₛTm, SubₛVar, vshift, weaken] at ih
--   sorry
--   done
-- | Γₛ, σ, .app (A := Aaa) t u => by
--   simp [SubₛVar, vshift, weaken]
--   done

theorem foo : (Γₛ : Conₛ) -> (σ : Subₛ Γₛ Γₛ) -> (v : Varₛ Γₛ Aₛ) -> vshift (SubₛVar v σ) = SubₛVar v (weaken (Aₛ := Bₛ) σ)
| Γₛ ▹ Bₛ, .cons σ s, .vz => by simp [SubₛVar, vshift, weaken]
| Γₛ ▹ Bₛ, .cons σ s, .vs v => by
  simp [SubₛVar, vshift, weaken]
  let v' := SubₛVar v σ
  -- have ih := foo Γₛ σ v'
  sorry
  done

theorem SubₛVar_id : (v : Varₛ Γₛ Aₛ) -> SubₛVar v (Subₛ.id Γₛ) = .var v
| .vz => by rw [Subₛ.id, SubₛVar]
| .vs v => by
  have ih := SubₛVar_id v
  rw [Subₛ.id, SubₛVar]
  rw [<- foo]
  rw [ih]
  rfl

theorem SubₛTm_id' : {Γₛ : Conₛ} -> (t : Tmₛ Γₛ Aₛ) -> SubₛTm t (Subₛ.id Γₛ) = t
| .nil, t => False.elim <| Tmₛ_emptyCtx t
| .ext Γₛ Bₛ, .var v => by
  simp [SubₛVar_id, SubₛTm]
  -- rw [SubₛTm, Subₛ.id]
  -- match v with
  -- | vz => rw [SubₛVar]
  -- | vs v =>
  --   have ih := SubₛTm_id' (.var v)
  --   rw [SubₛTm] at ih
  --   rw [SubₛVar]
  --   have := congr_arg (vshift (Bₛ := Bₛ)) ih
  --   rw [vshift] at this
  --   -- rw [<- foo] -- !
  --   -- exact this
  --   done
| .ext Γₛ Bₛ, .app (A:=Cₛ) t u => by rw [SubₛTm, SubₛTm_id' t]


theorem SubₛTm_id : (t : Tmₛ Γₛ Aₛ) -> SubₛTm t (Subₛ.id Γₛ) = t
| .var v => by
  match v with
  | .vz => rw [SubₛTm, Subₛ.id, SubₛVar]
  | .vs (Γₛ := Δₛ) v =>
    have ih := SubₛTm_id (.var v)
    rw [SubₛTm] at ih
    rw [SubₛTm, Subₛ.id, SubₛVar]
    match Δₛ with
    | .nil =>
      rw [Subₛ.id]
      -- have := congr_arg (vshift (Bₛ := Aₛ)) ih
      -- sorry
      -- rw [vshift] at this
      -- rw [Subₛ.id] at ih
      -- done
      sorry
    | .ext Δₛ Bₛ => sorry
| .app (A := _Bₛ) t u => by rw [SubₛTm, SubₛTm_id t]

  -- induction t with
  -- | var v =>
  --   rw [SubₛTm]
  --   induction Γₛ with
  --   | nil => exact False.elim <| Tmₛ_emptyCtx (.var v)
  --   | ext Γₛ Bₛ ih =>
  --     rw [Subₛ.id]
  --     sorry
  --   done
  -- | app t u ih => sorry

  -- induction Γₛ  with
  -- | nil => exact False.elim <| Tmₛ_emptyCtx t
  -- | ext Γₛ Bₛ ih =>
  --   rw [Subₛ.id]
  --   sorry

-- #exit

-- ## Now for Points...

inductive Varₚ : Conₚ Γₛ -> Tyₚ Γₛ -> Type (u+1)
| vz :             Varₚ (Γ ▹ A) A
| vs : Varₚ Γ A -> Varₚ (Γ ▹ B) A

set_option genInjectivity false in
inductive Tmₚ.{u, v} {Γₛ : Conₛ.{u}} : Conₚ.{u} Γₛ -> Tyₚ.{u} Γₛ -> Type ((max u v)+1)
| var : Varₚ Γ A -> Tmₚ Γ A
| app {T : Type u} {A : T -> Tyₚ Γₛ} : Tmₚ Γ (PPi T A)   -> (t : T)      -> Tmₚ Γ (A t)
| appr             {A :      Tyₚ Γₛ} : Tmₚ Γ (PFunc a A) -> Tmₚ Γ (El a) -> Tmₚ Γ A

/-- Represents a substitution from Δₛ to Γₛ.
Note that `Subₛ` is essentially a list of the same length as the context `Δₛ`.
This is because for every entry in the context Δₛ we will substitute it
with a Γₛ-term saved in `Subₛ`, thus the resulting context will be Γₛ.  -/
inductive Subₚ : (Γ : Conₚ Γₛ) -> (Δ : Conₚ Δₛ) -> Type ((max u v)+1)
| nil : Subₚ Γ .nil
| cons : Subₚ Γ Δ -> Tmₚ.{u, v} Γ A -> Subₚ Γ (Δ ▹ A)

/-- Substitutes a variable `v ∈ Δₛ` with a Γₛ-term. -/
def SubₚVar : Varₚ Δ A -> Subₚ Γ Δ -> Tmₚ Γ A
| .vz  , .cons _ t => t
| .vs v, .cons σ _ => SubₚVar v σ

/-- Applies the substitution to a term, resulting in a new term in the new context. -/
def SubₚTm : {A : Tyₚ Γₛ} -> Tmₚ Δ A -> Subₚ Γ Δ -> Tmₚ Γ A
| _, .var v, σ => SubₚVar v σ
| _, .app (A := _A) t u, σ => .app (SubₚTm t σ) u
| _, .appr (A := A) t u, σ => .appr (SubₚTm t σ) (SubₚTm u σ)

def vsₚ : {A : Tyₚ Γₛ} -> Tmₚ Γ A -> Tmₚ (Γ ▹ B) A
| _, .var v => .var (.vs v)
| _, .app  (A := _A) t u => .app  (vsₚ t) u
| _, .appr (A := _A) t u => .appr (vsₚ t) (vsₚ u)

def weakenₚ.{u} : {Γ Δ : Conₚ.{u} Γₛ} -> {A : Tyₚ.{u} Γₛ} -> Subₚ.{u} Γ Δ -> Subₚ (Γ ▹ A) Δ
| _, ⬝  , _, .nil => .nil
| _, _ ▹ _, _, .cons σ t => .cons (weakenₚ σ) (vsₚ t)

def Subₚ.id : (Γ : Conₚ Γₛ) -> Subₚ Γ Γ
| ⬝ => .nil
| Γ ▹ _ => .cons (weakenₚ (Subₚ.id Γ)) (.var .vz)

theorem Tmₚ_emptyCtx (t : Tmₚ ⬝ A) : False := by
  induction t with
  | var v => cases v
  | app _ _ ih => exact ih
  | appr _ _ ih => exact ih


-- theorem SubₚTm_id (t : Tmₚ Γ A) : SubₚTm t (Subₚ.id Γ) = t := by
--   -- induction Γ with
--   -- | nil => exfalso; exact Tmₚ_emptyCtx t
--   -- | ext Γ B ih =>
--   --   rw [Subₚ.id]
--   --   rw [weakenₚ]
--   --   done
--   induction t with
--   | var v =>
--     rw [SubₚTm]
--     sorry
--   | app t u ih => sorry
--   | appr t u ihₜ ihᵤ => sorry

def VarₚA : Varₚ Γ A -> ConₚA Γ γₛ -> TyₚA A γₛ
| .vz  , ⟨_, a⟩ => a
| .vs v, ⟨γ, _⟩ => VarₚA v γ

def TmₚA.{u} : {A : Tyₚ Γₛ} -> Tmₚ.{u} Γ A -> ConₚA.{u} Γ γₛ -> TyₚA.{u} A γₛ
| _, .var v, γ => VarₚA v γ
| _, .app (A := _A) t u, γ => (TmₚA t γ) u
| _, .appr (A := _) t u, γ => (TmₚA t γ) (TmₚA u γ)

def SubₚA : Subₚ Γ Δ -> ConₚA Γ γₛ -> ConₚA Δ γₛ
| .nil     ,  _ => ⟨⟩
| .cons σ t, γₛ => ⟨SubₚA σ γₛ, TmₚA t γₛ⟩

def VarₚD : (x : Varₚ Γ A) -> ConₚD Γ γₛD γ -> TyₚD A γₛD (VarₚA x γ)
| .vz  , ⟨ _, aD⟩ => aD
| .vs v, ⟨γD,  _⟩ => VarₚD v γD

-- This works but TmₛA_var doesn't work by rfl?
theorem TmₚA_var : TmₚA (Tmₚ.var v) γₛ = VarₚA v γₛ := by rfl

def TmₚD : (t : Tmₚ Γ A) -> ConₚD Γ γₛD γ -> TyₚD A γₛD (TmₚA t γ)
| .var v, γD => VarₚD v γD
| .app (A := _A) t u, γD => TmₚD t γD u
| .appr (A := A) t u, γD => TmₚD t γD (TmₚD u γD)

def SubₚD : (σ : Subₚ Γ Δ) -> ConₚD Γ γₛD γ -> ConₚD Δ γₛD (SubₚA σ γ)
| .nil, γD => ⟨⟩
| .cons σ t, γD => ⟨SubₚD σ γD, TmₚD t γD⟩

theorem Subₚ_Varₚ {σ : Subₚ Γ Δ} {v : Varₚ Δ A} : TmₚA (SubₚVar v σ) γ = VarₚA v (SubₚA σ γ) := by
  induction v with
  | vz => let .cons σ t := σ; rfl
  | vs v ih => let .cons σ _ := σ; apply ih

theorem Subₚ_Tmₚ {σ : Subₚ Γ Δ} {t : Tmₚ Δ A} : TmₚA (SubₚTm t σ) γ = TmₚA t (SubₚA σ γ) := by
  induction t with
  | var v => rw [TmₚA]; exact Subₚ_Varₚ
  | app t u ih => simp_all only [SubₚTm, TmₚA]
  | appr t u ihₜ ihᵤ => simp_all only [SubₚTm, TmₚA]

-- # Sort and Points Constructors

-- set_option pp.universes true

-- The paper assumes `u := 0` but we generalize a little.
universe u
variable (Ωₛ : Conₛ.{u})
variable (Ωₚ : Conₚ.{u} Ωₛ)

/-- Constructs a sort constructor from a mutual block.
You then do, for example
```
def Even : Nat -> Type := constrₛTy ...
```

This is a lambda telescope which eventually produces a type for the point terms term Ω⊢t.
Then later constrTmₚ will produce the actual terms which inhabit this type.
We will soon prove *coherence* of this, which will "pull back" any meaning about the syntactic terms and types
to meaning about the actual Lean terms and types.

Example.
Try not to get confused by `V String`, just imagine it's one identifier.
```
constrₛTy (Ωₛ := Vₛ) (Ω := V String) (Aₛ := (SPi Nat (fun _ => U))) (.var .vz)
```
reduces to
```
fun (n : Nat) => Tmₚ (V String) (El ((.var .vz) @ n))    :   Nat -> Type
```
which is a stand-in for `Vec String : Nat -> Type`.
We do not have an actual `Vec String`, so instead we use `constrTmₛ (V String)`
-/
def mkTyₛ (Ωₛ : Conₛ.{u}) (Ωₚ : Conₚ.{u} Ωₛ) : {Aₛ : Tyₛ.{u}} -> Tmₛ.{u} Ωₛ Aₛ -> TyₛA.{u, (max u v) + 1} Aₛ
| U      , t => Tmₚ.{u, v} Ωₚ (El t)
| SPi X _, t => fun (x : X) => mkTyₛ Ωₛ Ωₚ (.app t x)

#check @mkTyₛ.{0, 0}

example : Type 1        := mkTyₛ.{0, 0} Vₛ (Vₚ String) (.app (.var .vz) 123) -- `Vec 123 : Type 1`
example : TyₛA.{0, 1} U := mkTyₛ Vₛ (Vₚ String) (.app (.var .vz) 123)
example : TyₛA (SPi Nat (fun _ => U)) := mkTyₛ Vₛ (Vₚ String) (.var .vz)
#reduce TyₛA (SPi Nat (fun _ => U))

/-- When you write `Vec : Nat -> Type` in Lean, that is a primitive constructor with no actual definition.
  Instead, here we *actually* provide a definition of that type, concretely
  `fun (n:Nat) => Tmₚ _ "Vec n" : Nat -> Type`. This makes sense because `Tmₚ _ _ : Type`.
  And later constructors `Vec.nil` etc will actually be defined to produce values of this type `Tmₚ _ _`. -/
example : mkTyₛ.{0, 0} Vₛ (Vₚ String) (Aₛ := (SPi Nat (fun _ => U))) (.var .vz)
  = fun (n : Nat) => Tmₚ.{0,0} (Vₚ String) (El (.app (.var .vz) n))
  := rfl

def mkConₛ' : Subₛ.{u} Ωₛ Γₛ -> ConₛA.{u, (max u v) + 1} Γₛ
| .nil => ⟨⟩
| .cons σ t => ⟨mkConₛ' σ, mkTyₛ.{u, v} Ωₛ Ωₚ t⟩

def mkConₛ : ConₛA.{u, (max u v) + 1} Ωₛ := mkConₛ'.{u, v} Ωₛ Ωₚ (Subₛ.id Ωₛ)

example : mkConₛ Vₛ (Vₚ String)
  = ⟨⟨⟩, fun (n : Nat) => Tmₚ (Vₚ String) (El (.app (Tmₛ.var .vz) n))⟩
  := rfl

theorem mkTyₛ_app (f : Tmₛ Ωₛ (SPi T Aₛ)) (τ : T) : mkTyₛ.{u, v} Ωₛ Ωₚ (Tmₛ.app f τ) = mkTyₛ.{u, v} Ωₛ Ωₚ f τ := rfl

theorem mkConₛ_coherent : (t : Tmₛ Γₛ Aₛ) -> (σ : Subₛ Ωₛ Γₛ) -> TmₛA.{u, (max u v) + 1} t (@mkConₛ'.{u, v} Ωₛ Ωₚ Γₛ σ) = @mkTyₛ.{u, v} Ωₛ Ωₚ Aₛ (SubₛTm t σ)
| t                 , .nil      => False.elim (Tmₛ_emptyCtx t)
| .var .vz          , .cons σ s => rfl
| .var (.vs v)      , .cons σ s => by
  have ih := mkConₛ_coherent (.var v) σ
  simp_all only [TmₛA, SubₛTm, VarₛA, SubₛVar]
| .app (A := Cₛ) f τ, .cons σ s => by rw [TmₛA_app, mkConₛ_coherent f (.cons σ s), SubₛTm]; rfl

example
  : @TyₚA Vₛ (PPi Nat fun n => @El Vₛ (.app (.var vz) n)) (mkConₛ Vₛ (Vₚ String))
  -- = ((n : Nat) -> (fun n => Tmₚ (V String) (El ((.var .vz) @ n))) n) -- intermediate step
  = ((n : Nat) -> Tmₚ (Vₚ String) (El (.app (.var .vz) n)))
  := rfl
example
  : @TyₚA Vₛ (El (.app (.var vz) 123)) (@mkConₛ Vₛ (Vₚ String))
  = Tmₚ (Vₚ String) (El (.app (.var .vz) 123))
  := rfl

-- theorem aux : TyₚA (El Self) (mkConₛ (Ω := Ω)) = Tmₚ.{u, v} Ω (El Self)
--   := by rw [TyₚA, mkConₛ, mkConₛ_coherent Self, mkTyₛ, SubₛTm_id]

def mkTyₚ : {A : Tyₚ _} -> Tmₚ Ωₚ A -> TyₚA A (mkConₛ Ωₛ Ωₚ)
| El Self, t => by
  -- this is actually `⊢ Tmₚ Ω (El Self)` but lean isn't smart enough
  rw [TyₚA]
  rw [mkConₛ]
  rw [mkConₛ_coherent _ _ Self]
  rw [mkTyₛ]
  rw [SubₛTm_id]
  exact t
| PPi T A, t => fun τ => mkTyₚ (.app t τ)
| PFunc Self A, t =>
  fun u =>
    let u : Tmₚ Ωₚ (El Self) := by
      rw [mkConₛ] at u
      rw [mkConₛ_coherent _ _ Self] at u
      rw [SubₛTm_id] at u
      exact u
    mkTyₚ (.appr t u)

#print axioms SubₛTm_id -- sorry

def mkConₚ' : Subₚ Ωₚ Γ -> ConₚA Γ (mkConₛ Ωₛ Ωₚ)
| .nil => ⟨⟩
| .cons σ t => ⟨mkConₚ' σ, mkTyₚ Ωₛ Ωₚ t⟩

def mkConₚ := mkConₚ' _ _ (Subₚ.id Ωₚ)

-- Lemma 18
theorem mkConₚ_coherent : (t : Tmₚ Γ A) -> (σ : Subₚ Ωₚ Γ) -> TmₚA t (@mkConₚ' Ωₛ Ωₚ Γ σ) = @mkTyₚ Ωₛ Ωₚ A (SubₚTm t σ)
| t                 , .nil      => False.elim (Tmₚ_emptyCtx t)
| .var .vz          , .cons σ s => by rw [mkConₚ', TmₚA, VarₚA]; rfl
| .var (.vs v)      , .cons σ s => by
  have ih := mkConₚ_coherent (.var v) σ
  simp_all only [TmₚA, SubₚTm, mkConₚ', VarₚA, SubₚVar]
| .app (A := Cₛ) f τ, .cons σ s => by
  rw [TmₚA]
  rw [mkConₚ_coherent f (.cons σ s)]
  rw [SubₚTm]
  rewrite [mkTyₚ]
  rfl
| .appr (A := Cₛ) f a, σ => by
  have ih₁ := mkConₚ_coherent f σ
  have ih₂ := mkConₚ_coherent a σ
  rw [TmₚA]
  rw [ih₁, ih₂]
  rw [SubₚTm]
  conv in mkTyₚ _ => unfold mkTyₚ
  rw [mkTyₚ]
  simp [Eq.mp, Eq.mpr, eq_cast_trans]
  sorry -- this broke when making Ωₛ and Ωₚ explicit somehow
  done

#print axioms mkConₚ_coherent

#check mkConₛ_coherent
#check mkConₚ_coherent


-- # Eliminator

variable (ωₛD : ConₛD Ωₛ (mkConₛ Ωₛ Ωₚ)) (ωₚD : ConₚD Ωₚ ωₛD (mkConₚ Ωₛ Ωₚ))

-- #check aux

def elimTyₛ : {Aₛ : Tyₛ.{u}} -> (t : Tmₛ.{u} Ωₛ Aₛ) -> TyₛS.{u, _} Aₛ (TmₛA t (mkConₛ Ωₛ Ωₚ)) (TmₛD t ωₛD)
| U, a =>
  -- a : Tmₛ Ωₛ U
  -- ⊢ TyₛS U (TmₛA a constrₛ) (TmₛD a ωₛD)
  -- have (ttt : TmₛA a (mkConₛ (Ω:=Ω))) : TyₛS.{0, 1} U (TmₛD a ωₛD ( (TmₚA (aux ▸ ttt) (mkConₚ (Ω:=Ω))))) = TmₛD a ωₛD ttt := sorry
  -- have (t : TmₛA a (@mkConₛ Ωₛ Ω)) : TyₛS U (TmₛD a ωₛD (TmₚA t (@mkConₚ Ωₛ Ω))) = sorry := sorry

  -- `t` is the thing we are eliminating.
  fun (t : TmₛA a (mkConₛ Ωₛ Ωₚ)) => by
    -- ⊢ TmₛD a ωₛD t
    -- let ret := TmₚD t ωₚD
    -- exact ret
    sorry
| SPi T Aₛ, t =>
  fun τ => by
    let res := elimTyₛ (.app t τ)
    rw [TyₛS_helper TmₛA_app] at res
    rw [TmₛD_app] at res
    simp only [eq_symm_cancel] at res
    exact res


def elimConₛ' : (σ : Subₛ Ωₛ Γₛ) -> ConₛS Γₛ (SubₛA σ (mkConₛ Ωₛ Ωₚ)) (SubₛD σ ωₛD)
| .nil => ⟨⟩
| .cons σ t => ⟨elimConₛ' σ, elimTyₛ Ωₛ Ωₚ ωₛD t⟩

def elimConₛ (ωₛD : ConₛD Ωₛ (mkConₛ Ωₛ Ωₚ)) : ConₛS Ωₛ (mkConₛ Ωₛ Ωₚ) ωₛD
  := by
    let res := elimConₛ' Ωₛ Ωₚ ωₛD (Subₛ.id Ωₛ)
    have h₁ := ConₛS_helper SubₛA_id (SubₛD (Subₛ.id Ωₛ) ωₛD)
    have h₂ : (@Eq.rec (ConₛA Ωₛ) (SubₛA (Subₛ.id Ωₛ) (mkConₛ Ωₛ Ωₚ)) (fun x _h => ConₛD Ωₛ x) (SubₛD (Subₛ.id Ωₛ) ωₛD) (mkConₛ Ωₛ Ωₚ) SubₛA_id) = ωₛD := by rw [SubₛD_id, eq_symm_cancel]
    rw [h₁, h₂] at res
    exact res

#print axioms elimConₛ

-- example : TmₛA t (SubₛA σ (mkConₛ (Ω:=Ω))) = TmₛA (SubₛTm t σ) (mkConₛ (Ω:=Ω)) := by
--   sorry

#check TmₛD_Subₛ
-- Transport hell
-- theorem lemma20 (σ : Subₛ Ωₛ Γₛ) (t : Tmₛ Γₛ Aₛ) : elimTyₛ ωₛD (SubₛTm t σ) = TmₛA_Subₛ ▸ TmₛD_Subₛ' ▸ TmₛS t (elimConₛ' ωₛD σ)
--   := sorry

theorem elimTyₚ (t : Tmₚ Ωₚ A) : TyₚS A (elimConₛ Ωₛ Ωₚ ωₛD) (TmₚA t (mkConₚ Ωₛ Ωₚ)) (TmₚD t ωₚD) := by
  induction A with
  | El         Self        =>
    rw [TyₚS]
    -- rw [mkConₛ_coherent]
    unfold mkConₚ
    -- have h := mkConₚ_coherent t (Subₚ.id Ω)
    -- rw [h]
    -- conv => lhs; rw [h]
    sorry
  | PPi   T    Rest ihRest => sorry
  | PFunc Self Rest ihRest => sorry

theorem elimConₚ (σ : Subₚ Ωₚ Γ) : ConₚS Γ (elimConₛ Ωₛ Ωₚ ωₛD) (SubₚA σ (mkConₚ Ωₛ Ωₚ)) (SubₚD σ ωₚD) := sorry

















namespace Example.Constructing
  def Vec (A : Type) : Nat -> Type 1                                 := mkTyₛ Vₛ (Vₚ A) (.var .vz)
  def Vec.nil (A : Type) : Vec A 0                                   := mkTyₚ Vₛ (Vₚ A) (.var (.vs .vz)) -- de brujin index 1
  def Vec.cons (A : Type) : (n : Nat) -> A -> Vec A n -> Vec A (n+1) := mkTyₚ Vₛ (Vₚ A) (.var .vz) -- de brujin index 0

  #reduce Vec String 0
  #reduce Vec.nil
  #reduce Vec.nil Nat
  #reduce Vec.cons
  #reduce Vec.cons Nat 0 123 (Vec.nil Nat)

  def Vec.recs {A} (dₛ : ConₛD Vₛ (mkConₛ Vₛ (Vₚ A))) : ConₛS Vₛ (mkConₛ Vₛ (Vₚ A)) dₛ := elimConₛ Vₛ (Vₚ A) dₛ -- all recs for the mutual block
  def Vec.rec' {A} (dₛ : ConₛD Vₛ (mkConₛ Vₛ (Vₚ A))) : TyₛS (SPi Nat fun _ => U) (TmₛA (Tmₛ.var vz) (mkConₛ Vₛ (Vₚ A))) (TmₛD (Tmₛ.var vz) dₛ) := elimTyₛ Vₛ (Vₚ A) dₛ (.var .vz)
  -- def Vec.rec.nil {A} (dₛ : ConₛD Vₛ (mkConₛ (Ω:=V A))) : TyₚS _ _ _ _ := elimTyₚ dₛ (.var (.vs .vz))
  -- theorem Vec.rec.cons := elimₚ
  #check Vec.recs
  #check Vec.rec
end Example.Constructing
