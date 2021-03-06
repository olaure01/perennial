From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

From Perennial.program_proof Require Import proof_prelude.
From Goose.github_com.mit_pdos.goose_nfsd Require Import addr.

Section heap.
Context `{!heapG Σ}.
Context `{!lockG Σ}.

Implicit Types s : Slice.t.
Implicit Types (stk:stuckness) (E: coPset).

Record addr := {
  addrBlock : u64;
  addrOff : u64;
}.

Global Instance addr_eq_dec : EqDecision addr.
Proof.
  solve_decision.
Defined.

Global Instance addr_finite : Countable addr.
Proof.
  refine (inj_countable'
            (fun a => (a.(addrBlock), a.(addrOff)))
            (fun '(b, o) => Build_addr b o) _);
    by intros [].
Qed.

Definition addr2val (a : addr) : val :=
  (#a.(addrBlock), (#a.(addrOff), #())).

Definition addr2flat_z (a : addr) : Z :=
  int.val a.(addrBlock) * block_bytes * 8 + int.val a.(addrOff).

Definition addr2flat (a : addr) : u64 :=
  addr2flat_z a.

Definition valid_addr (a : addr) : Prop :=
  int.val a.(addrOff) < block_bytes*8 ∧
  int.val a.(addrBlock) * block_bytes < 2^64 ∧
  int.val a.(addrBlock) * block_bytes * 8 < 2^64 ∧
  addr2flat_z a < 2^64.

Theorem addr2flat_z_eq `(valid_addr a0) `(valid_addr a1) :
  addr2flat a0 = addr2flat a1 →
  addr2flat_z a0 = addr2flat_z a1.
Proof.
  destruct a0, a1.
  unfold addr2flat, valid_addr, addr2flat_z, block_bytes in *.
  simpl in *; intuition.
  apply (f_equal int.val) in H.
  revert H.
  word.
Qed.

Theorem addr2flat_eq `(valid_addr a0) `(valid_addr a1) :
  addr2flat a0 = addr2flat a1 →
  a0 = a1.
Proof.
  intros.
  eapply addr2flat_z_eq in H; eauto.
  destruct a0, a1.
  unfold valid_addr, addr2flat_z, block_bytes in *.
  simpl in *.
  intuition.
  replace addrOff0 with addrOff1 in *.
  { replace addrBlock0 with addrBlock1; auto.
    assert (int.val addrBlock0 * Z.to_nat 4096 * 8 = int.val addrBlock1 * Z.to_nat 4096 * 8) by lia.
    word.
  }
  word.
Qed.

Theorem addr2flat_ne `(valid_addr a0) `(valid_addr a1) :
  a0 ≠ a1 ->
  addr2flat a0 ≠ addr2flat a1.
Proof.
  intros; intuition.
  apply H.
  eapply addr2flat_eq; eauto.
Qed.

Set Implicit Arguments.

Section flatid2addr.

  Variable (T : Type).

  Definition flatid_addr_map (fm : gmap u64 T) (am : gmap addr T) : Prop :=
    ( ∀ a v, am !! a = Some v -> valid_addr a ∧ fm !! (addr2flat a) = Some v ) ∧
    ( ∀ fa v, fm !! fa = Some v -> ∃ a, valid_addr a ∧ addr2flat a = fa ∧ am !! a = Some v ).

  Theorem flatid_addr_lookup fm am a :
    flatid_addr_map fm am ->
    valid_addr a ->
    fm !! (addr2flat a) = am !! a.
  Proof.
    unfold flatid_addr_map; intros.
    destruct (am !! a) eqn:Heq.
    - apply H; eauto.
    - destruct (fm !! addr2flat a) eqn:Heq2; eauto.
      apply H in Heq2; eauto.
      destruct Heq2; intuition idtac.
      apply addr2flat_eq in H1; eauto; subst.
      congruence.
  Qed.

  Theorem flatid_addr_insert fm am a v :
    flatid_addr_map fm am ->
    valid_addr a ->
    flatid_addr_map (<[addr2flat a := v]> fm) (<[a := v]> am).
  Proof.
    rewrite /flatid_addr_map; split; intros.
    - destruct (decide (a = a0)); subst.
      + rewrite lookup_insert in H1; inversion H1; clear H1; subst.
        repeat rewrite -> lookup_insert; eauto.
      + rewrite -> lookup_insert_ne in H1 by eauto.
        apply H in H1; intuition eauto.
        rewrite -> lookup_insert_ne by (apply addr2flat_ne; eauto).
        eauto.
    - destruct (decide (addr2flat a = fa)); subst.
      + rewrite lookup_insert in H1; inversion H1; clear H1; subst.
        eexists.
        repeat rewrite -> lookup_insert; eauto.
      + rewrite -> lookup_insert_ne in H1 by eauto.
        apply H in H1; destruct H1. intuition eauto.
        exists x; intuition eauto.
        rewrite -> lookup_insert_ne; eauto.
        congruence.
  Qed.

  Theorem flatid_addr_insert_inv_2 fm am a v :
    flatid_addr_map fm (<[a := v]> am) ->
      valid_addr a ∧
      fm !! (addr2flat a) = Some v ∧
      flatid_addr_map (delete (addr2flat a) fm) (delete a am).
  Proof.
    intros.
    destruct H.
    edestruct H.
    { erewrite lookup_insert; eauto. }
    intuition eauto.
    split; intros.
    - destruct (decide (a = a0)); subst.
      { rewrite lookup_delete in H3; congruence. }
      rewrite lookup_delete_ne in H3; eauto.
      edestruct H.
      { rewrite lookup_insert_ne; eauto. }
      intuition eauto.
      rewrite lookup_delete_ne; eauto.
      eapply addr2flat_ne; eauto.
    - destruct (decide (addr2flat a = fa)); subst.
      { rewrite lookup_delete in H3; congruence. }
      rewrite lookup_delete_ne in H3; eauto.
      apply H0 in H3. destruct H3.
      exists x. intuition eauto.
      rewrite -> lookup_insert_ne in H6 by congruence.
      rewrite -> lookup_delete_ne by congruence.
      eauto.
  Qed.

  Theorem flatid_addr_insert_inv_1 fm am fa v :
    flatid_addr_map (<[fa := v]> fm) am ->
    ∃ a,
      valid_addr a ∧
      fa = addr2flat a ∧
      am !! a = Some v ∧
      flatid_addr_map (delete fa fm) (delete a am).
  Proof.
    intros.
    destruct H.
    edestruct H0.
    { erewrite lookup_insert; eauto. }
    exists x.
    intuition eauto.
    split; intros.
    - destruct (decide (a = x)); subst.
      { rewrite lookup_delete in H3; congruence. }
      rewrite lookup_delete_ne in H3; eauto.
      edestruct H; eauto.
      intuition eauto.
      rewrite -> lookup_insert_ne in H5 by (apply addr2flat_ne; eauto).
      rewrite lookup_delete_ne; eauto.
      eapply addr2flat_ne; eauto.
    - destruct (decide (fa = fa0)); subst.
      { rewrite lookup_delete in H3; congruence. }
      rewrite lookup_delete_ne in H3; eauto.
      edestruct H0.
      { rewrite lookup_insert_ne; eauto. }
      exists x0; intuition eauto.
      rewrite -> lookup_delete_ne by congruence.
      eauto.
  Qed.

  Theorem flatid_addr_delete fm am a :
    flatid_addr_map fm am ->
    valid_addr a ->
    flatid_addr_map (delete (addr2flat a) fm) (delete a am).
  Proof.
    rewrite /flatid_addr_map; split; intros.
    - destruct (decide (a = a0)); subst.
      + rewrite lookup_delete in H1; congruence.
      + rewrite -> lookup_delete_ne in H1 by eauto.
        apply H in H1; intuition eauto.
        rewrite -> lookup_delete_ne by (apply addr2flat_ne; eauto).
        eauto.
    - destruct (decide (addr2flat a = fa)); subst.
      + rewrite lookup_delete in H1; congruence.
      + rewrite -> lookup_delete_ne in H1 by eauto.
        apply H in H1; destruct H1.
        exists x; intuition eauto.
        rewrite lookup_delete_ne; eauto.
        congruence.
  Qed.

  Theorem flatid_addr_empty :
    flatid_addr_map ∅ ∅.
  Proof.
    unfold flatid_addr_map; split; intros.
    - rewrite lookup_empty in H; congruence.
    - rewrite lookup_empty in H; congruence.
  Qed.

  Theorem flatid_addr_empty_1 m :
    flatid_addr_map ∅ m -> m = ∅.
  Proof.
    unfold flatid_addr_map; intros.
    apply map_empty; intros.
    destruct (m !! i) eqn:He; eauto.
    apply H in He. rewrite lookup_empty in He. intuition congruence.
  Qed.

  Theorem flatid_addr_empty_2 m :
    flatid_addr_map m ∅ -> m = ∅.
  Proof.
    unfold flatid_addr_map; intros.
    apply map_empty; intros.
    destruct (m !! i) eqn:He; eauto.
    apply H in He. destruct He. rewrite lookup_empty in H0. intuition congruence.
  Qed.

End flatid2addr.


Section map.
  Context {PROP : bi}.
  Context `{Countable K} {A : Type}.

  Theorem big_sepM_flatid_addr_map_1 (Φ : _ -> A -> PROP) fm am :
    flatid_addr_map fm am ->
    ([∗ map] a↦b ∈ am, Φ a b) -∗ [∗ map] fa↦b ∈ fm, ∃ a, ⌜ fa = addr2flat a ⌝ ∗ Φ a b.
  Proof.
    rewrite <- (list_to_map_to_list am).
    pose proof (NoDup_fst_map_to_list am); revert H0.
    generalize (map_to_list am); intros l H0.
    clear am; intros.
    iIntros "H".

    iInduction l as [|] "IH" forall (fm H0 H1).
    - simpl in *. apply flatid_addr_empty_2 in H1. rewrite H1.
      repeat rewrite big_sepM_empty. done.
    - simpl in *. inversion H0; clear H0; subst.
      apply flatid_addr_insert_inv_2 in H1; intuition idtac.
      iDestruct (big_sepM_insert_delete with "H") as "[Ha H]".
      erewrite <- (insert_id fm) by eauto.
      iApply big_sepM_insert_delete.
      iSplitL "Ha".
      { iExists _; iFrame. done. }
      rewrite delete_notin.
      2: { apply not_elem_of_list_to_map_1; eauto. }
      rewrite -> (delete_notin (list_to_map _)) in H3.
      2: { apply not_elem_of_list_to_map_1; eauto. }
      iDestruct ("IH" $! _ H5 H3 with "H") as "H".
      iFrame.
  Qed.

  Theorem big_sepM_flatid_addr_map_2 (Φ : _ -> A -> PROP) fm am :
    flatid_addr_map fm am ->
    ([∗ map] fa↦b ∈ fm, Φ fa b) -∗ [∗ map] a↦b ∈ am, Φ (addr2flat a) b.
  Proof.
    rewrite <- (list_to_map_to_list fm).
    pose proof (NoDup_fst_map_to_list fm); revert H0.
    generalize (map_to_list fm); intros l H0.
    clear fm; intros.
    iIntros "H".

    iInduction l as [|] "IH" forall (am H0 H1).
    - simpl in *. apply flatid_addr_empty_1 in H1. rewrite H1.
      repeat rewrite big_sepM_empty. done.
    - simpl in *. inversion H0; clear H0; subst.
      apply flatid_addr_insert_inv_1 in H1; destruct H1; intuition subst.
      iDestruct (big_sepM_insert_delete with "H") as "[Ha H]".
      erewrite <- (insert_id am) by eauto.
      iApply big_sepM_insert_delete.
      iSplitL "Ha".
      { rewrite H0. iFrame. }
      rewrite delete_notin.
      2: { apply not_elem_of_list_to_map_1; eauto. }
      rewrite -> (delete_notin (list_to_map _)) in H6.
      2: { apply not_elem_of_list_to_map_1; eauto. }
      iDestruct ("IH" $! _ H5 H6 with "H") as "H".
      iFrame.
  Qed.

End map.


Hint Unfold block_bytes : word.
Hint Unfold valid_addr : word.
Hint Unfold addr2flat : word.
Hint Unfold addr2flat_z : word.

Theorem wp_Addr__Flatid a :
  {{{
    ⌜ valid_addr a ⌝
  }}}
    Addr__Flatid (addr2val a)
  {{{
    v, RET #v; ⌜ v = addr2flat a ⌝
  }}}.
Proof.
  iIntros (Φ) "% HΦ".
  wp_call.
  iApply "HΦ".
  iPureIntro.

  word_cleanup.
  rewrite ?word.unsigned_mul. (* XXX why is this needed? *)
  word_cleanup.
Qed.

End heap.
