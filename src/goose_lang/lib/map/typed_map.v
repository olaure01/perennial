From Perennial.goose_lang Require Import notation proofmode typing.
From Perennial.goose_lang.lib Require Import typed_mem into_val.
From Perennial.goose_lang.lib Require Import map.impl.
From Perennial.goose_lang.lib Require map.map.
Import uPred.

From iris_string_ident Require Import ltac2_string_ident.

Set Default Proof Using "Type".

Module Map.
  Definition t V {ext} `{@IntoVal ext V} := gmap u64 V.
  Definition untype `{IntoVal V}:
    t V -> gmap u64 val * val :=
    fun m => (to_val <$> m, to_val IntoVal_def).
End Map.

Section heap.
Context `{ffi_sem: ext_semantics} `{!ffi_interp ffi} `{!heapG Σ}.
Context {ext_ty: ext_types ext}.

Context `{!IntoVal V}.
Context `{!IntoValForType IntoVal0 t}.

Implicit Types (m: Map.t V) (k: u64) (v:V).

Definition map_get m k : V * bool :=
  let r := default IntoVal_def (m !! k) in
  let ok := bool_decide (is_Some (m !! k)) in
  (r, ok).

Definition map_insert m k v : Map.t V :=
  <[ k := v ]> m.

Definition map_del m k : Map.t V :=
  delete k m.

Lemma map_get_true k v m :
  map_get m k = (v, true) ->
  m !! k = Some v.
Proof.
  rewrite /map_get.
  destruct (m !! k); rewrite /=; congruence.
Qed.

Lemma map_get_false k v m :
  map_get m k = (v, false) ->
  m !! k = None ∧ v = IntoVal_def.
Proof.
  rewrite /map_get.
  destruct (m !! k); rewrite /=.
  - congruence.
  - intuition congruence.
Qed.

Definition is_map (mref:loc) (m: Map.t V) :=
  map.is_map mref (Map.untype m).

Theorem is_map_untype mref m : is_map mref m -∗ map.is_map mref (Map.untype m).
Proof.
  auto.
Qed.

Theorem is_map_retype mref m : map.is_map mref (to_val <$> m, to_val IntoVal_def) -∗ is_map mref m.
Proof.
  auto.
Qed.

Ltac untype :=
  rewrite /is_map /Map.untype.

Theorem wp_NewMap stk E :
  {{{ True }}}
    ref (zero_val (mapValT t)) @ stk; E
  {{{ mref, RET #mref;
      is_map mref ∅ }}}.
Proof using IntoValForType0.
  iIntros (Φ) "_ HΦ".
  wp_apply map.wp_NewMap.
  iIntros (mref) "Hm".
  iApply "HΦ".
  iApply is_map_retype.
  rewrite def_is_zero fmap_empty.
  auto.
Qed.

Lemma map_get_fmap {m} {k} {vv: val} {ok: bool} :
  map.map_get (Map.untype m) k = (vv, ok) ->
  exists v, vv = to_val v ∧
            map_get m k = (v, ok).
Proof.
  rewrite /map.map_get /map_get.
  rewrite /Map.untype.
  intros H; inversion H; subst; clear H.
  destruct ((to_val <$> m) !! k) eqn:Hlookup; simpl; eauto.
  - rewrite lookup_fmap in Hlookup.
    apply fmap_Some in Hlookup as [x [Hlookup ->]].
    rewrite Hlookup; eauto.
  - eexists; intuition eauto.
    rewrite lookup_fmap in Hlookup.
    apply fmap_None in Hlookup.
    rewrite Hlookup; auto.
Qed.

Theorem wp_MapGet stk E mref m k :
  {{{ is_map mref m }}}
    MapGet #mref #k @ stk; E
  {{{ v ok, RET (to_val v, #ok);
      ⌜map_get m k = (v, ok)⌝ ∗
      is_map mref m }}}.
Proof.
  iIntros (Φ) "Hm HΦ".
  iDestruct (is_map_untype with "Hm") as "Hm".
  wp_apply (map.wp_MapGet with "Hm").
  iIntros (vv ok) "(%Hmapget&Hm)".
  apply map_get_fmap in Hmapget as [v [-> Hmapget]].
  iApply "HΦ".
  iSplit; [ auto | ].
  iApply (is_map_retype with "Hm").
Qed.

Theorem map_insert_untype m k v' :
  map.map_insert (Map.untype m) k (to_val v') =
  Map.untype (map_insert m k v').
Proof.
  untype.
  rewrite /map.map_insert /map_insert.
  rewrite fmap_insert //.
Qed.

Theorem map_del_untype m k :
  map.map_del (Map.untype m) k =
  Map.untype (map_del m k).
Proof.
  untype.
  rewrite /map.map_del /map_del.
  rewrite fmap_delete //.
Qed.

Theorem wp_MapInsert stk E mref m k v' vv :
  vv = to_val v' ->
  {{{ is_map mref m }}}
    MapInsert #mref #k vv @ stk; E
  {{{ RET #(); is_map mref (map_insert m k v') }}}.
Proof.
  intros ->.
  iIntros (Φ) "Hm HΦ".
  iDestruct (is_map_untype with "Hm") as "Hm".
  wp_apply (map.wp_MapInsert with "Hm").
  iIntros "Hm".
  iApply "HΦ".
  rewrite map_insert_untype.
  iApply (is_map_retype with "Hm").
Qed.

Theorem wp_MapInsert_to_val stk E mref m k v' :
  {{{ is_map mref m }}}
    MapInsert #mref #k (to_val v') @ stk; E
  {{{ RET #(); is_map mref (map_insert m k v') }}}.
Proof.
  iIntros (Φ) "Hm HΦ".
  iApply (wp_MapInsert with "Hm"); first reflexivity.
  iFrame.
Qed.

Theorem wp_MapDelete stk E mref m k :
  {{{ is_map mref m }}}
    MapDelete #mref #k @ stk; E
  {{{ RET #(); is_map mref (map_del m k) }}}.
Proof.
  iIntros (Φ) "Hm HΦ".
  iDestruct (is_map_untype with "Hm") as "Hm".
  wp_apply (map.wp_MapDelete with "Hm").
  iIntros "Hm".
  iApply "HΦ".
  rewrite map_del_untype.
  iApply (is_map_retype with "Hm").
Qed.

Theorem wp_MapIter stk E mref m (I: iProp Σ) (P Q: u64 -> V -> iProp Σ) (body: val) Φ:
  is_map mref m -∗
  I -∗
  ([∗ map] k ↦ v ∈ m, P k v) -∗
  (∀ (k: u64) (v: V),
      {{{ I ∗ P k v }}}
        body #k (to_val v) @ stk; E
      {{{ RET #(); I ∗ Q k v }}}) -∗
  ((is_map mref m ∗ I ∗ [∗ map] k ↦ v ∈ m, Q k v) -∗ Φ #()) -∗
  WP MapIter #mref body @ stk; E {{ v, Φ v }}.
Proof.
  iIntros "Hm HI HP #Hbody HΦ".
  iDestruct (is_map_untype with "Hm") as "Hm".
  wp_apply (map.wp_MapIter _ _ _ _ _
    (λ k vv, ∃ v, ⌜vv = to_val v⌝ ∗ P k v)%I
    (λ k vv, ∃ v, ⌜vv = to_val v⌝ ∗ Q k v)%I with "Hm HI [HP] [Hbody]").
  { rewrite /Map.untype /=.
    iApply big_sepM_fmap.
    iApply (big_sepM_mono with "HP").
    iIntros.
    iExists _; iFrame; done. }
  { iIntros.
    iIntros (Φbody).
    iModIntro.
    iIntros "[HI HP] HΦ".
    iDestruct "HP" as (v0) "[-> HP]".
    wp_apply ("Hbody" with "[$HI $HP]").
    iIntros "[HI HQ]".
    iApply "HΦ"; iFrame.
    iExists _; iFrame; done. }
  iIntros "(Hm & HI & HQ)".
  iApply "HΦ". iFrame.
  rewrite /Map.untype /=.
Admitted.

Theorem wp_MapIter_2 stk E mref m (I: gmap u64 V -> gmap u64 V -> iProp Σ) (body: val) Φ:
  is_map mref m -∗
  I m ∅ -∗
  (∀ (k: u64) (v: V) (mtodo mdone : gmap u64 V),
      {{{ I mtodo mdone ∗ ⌜mtodo !! k = Some v⌝ }}}
        body #k (to_val v) @ stk; E
      {{{ RET #(); I (delete k mtodo) (<[k := v]> mdone) }}}) -∗
  ((is_map mref m ∗ I ∅ m) -∗ Φ #()) -∗
  WP MapIter #mref body @ stk; E {{ v, Φ v }}.
Proof.
Admitted.

End heap.

Arguments wp_NewMap {_ _ _ _ _ _ _} V {_} {t}.
Arguments wp_MapGet {_ _ _ _ _ _} V {_} {_ _}.
Arguments wp_MapInsert {_ _ _ _ _ _} V {_} {_ _}.
Arguments wp_MapDelete {_ _ _ _ _ _} V {_} {_ _}.
