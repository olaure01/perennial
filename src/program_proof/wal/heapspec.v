From RecordUpdate Require Import RecordSet.
Import RecordSetNotations.

From Goose.github_com.mit_pdos.goose_nfsd Require Import wal.

From Perennial.Helpers Require Import Transitions.
From Perennial.program_proof Require Import proof_prelude wal.abstraction wal.specs.
From Perennial.algebra Require Import deletable_heap.

Inductive heap_block :=
| HB (installed_block : Block) (blocks_since_install : list Block)
.

Section heap.

Context `{!heapG Σ}.
Context `{!gen_heapPreG u64 heap_block Σ}.
Context (N: namespace).

(* Invariant and definitions *)

Definition wal_heap_inv_addr (ls : log_state.t) (a : u64) (b : heap_block) : iProp Σ :=
  ⌜ match b with
    | HB installed_block blocks_since_install =>
      ∃ (txn_id : nat),
        txn_id ≤ ls.(log_state.installed_lb) ∧
        disk_at_txn_id txn_id ls !! int.val a = Some installed_block ∧
        updates_since txn_id a ls = blocks_since_install
    end ⌝.

Definition wal_heap_inv (γh : gen_heapG u64 heap_block Σ) (ls : log_state.t) : iProp Σ :=
   ∃ (gh : gmap u64 heap_block),
      gen_heap_ctx (hG := γh) gh ∗
                   [∗ map] a ↦ b ∈ gh, wal_heap_inv_addr ls a b.


(* Helper lemmas *)


Theorem apply_upds_cons disk u ul :
  apply_upds (u :: ul) disk =
  apply_upds ul (apply_upds [u] disk).
Proof.
  reflexivity.
Qed.

Theorem apply_upds_app : forall u1 u2 disk,
  apply_upds (u1 ++ u2) disk =
  apply_upds u2 (apply_upds u1 disk).
Proof.
  induction u1.
  - reflexivity.
  - simpl app.
    intros.
    rewrite apply_upds_cons.
    rewrite IHu1.
    reflexivity.
Qed.

Theorem txn_upds_cons txn txnl:
  txn_upds (txn :: txnl) =
  txn_upds [txn] ++ txn_upds txnl.
Proof.
  unfold txn_upds.
  rewrite <- concat_app.
  rewrite <- fmap_app.
  f_equal.
Qed.

Theorem take_drop_txns:
  forall (txn_id: nat) txns,
    txn_id <= length txns ->
    txn_upds txns = txn_upds (take txn_id txns) ++ txn_upds (drop txn_id txns).
Proof.
  induction txn_id.
  - intros.
    unfold txn_upds; simpl.
    rewrite skipn_O; auto.
  - intros. destruct txns.
    + unfold txn_upds; simpl; auto.
    + rewrite txn_upds_cons.
      rewrite firstn_cons.
      rewrite skipn_cons.
      replace (txn_upds (p :: take txn_id txns)) with (txn_upds [p] ++ txn_upds (take txn_id txns)).
      2: rewrite <- txn_upds_cons; auto.
      rewrite <- app_assoc.
      f_equal.
      rewrite <- IHtxn_id; auto.
      rewrite cons_length in H.
      lia.
Qed.

Theorem updates_since_to_last_disk σ a (txn_id : nat) installed :
  wal_wf σ ->
  disk_at_txn_id txn_id σ !! int.val a = Some installed ->
  (txn_id ≤ σ.(log_state.installed_lb))%nat ->
  last_disk σ !! int.val a = Some (latest_update installed (updates_since txn_id a σ)).
Proof.
  destruct σ.
  unfold last_disk, updates_since, disk_at_txn_id.
  simpl.
  intros.
  rewrite firstn_all.
  rewrite (take_drop_txns txn_id txns).
  2: {
    unfold wal_wf in H; intuition; simpl in *.
    lia.
  }
  rewrite apply_upds_app.
  generalize dependent H0.
  generalize (apply_upds (txn_upds (take txn_id txns)) d).
  intros.
  generalize (txn_upds (drop txn_id txns)).
  intros.
  generalize dependent d0.
  generalize dependent installed.
  induction l; simpl; intros.
  - auto.
  - destruct a0. unfold updates_for_addr.
    rewrite filter_cons; simpl.
    destruct (decide (addr = a)); subst.
    + simpl.
      erewrite <- IHl.
      { reflexivity. }
      rewrite lookup_insert. auto.
    + erewrite <- IHl.
      { reflexivity. }
      rewrite lookup_insert_ne; auto.
      intro Hx. apply n. word.
Qed.

Theorem no_updates_since_last_disk σ a (txn_id : nat) :
  wal_wf σ ->
  no_updates_since σ a txn_id ->
  disk_at_txn_id txn_id σ !! int.val a = last_disk σ !! int.val a.
Proof.
Admitted.

Theorem no_updates_since_nil σ a (txn_id : nat) :
  wal_wf σ ->
  no_updates_since σ a txn_id ->
  updates_since txn_id a σ = nil.
Proof.
Admitted.

Theorem wal_wf_advance_installed_to σ txn_id :
  wal_wf σ ->
  (* is_trans σ.(log_state.trans) pos -> *)
  (txn_id ≤ σ.(log_state.durable_lb))%nat ->
  wal_wf (set log_state.installed_lb (λ _ : nat, txn_id) σ).
Proof.
  destruct σ.
  unfold wal_wf; simpl.
  intuition.
  lia.
Qed.

(* TODO: rename pos to txn_id *)
Theorem updates_since_apply_upds σ a (pos diskpos : nat) installedb b :
  (pos ≤ diskpos)%nat ->
  (diskpos <= length (log_state.txns σ))%nat ->
  disk_at_txn_id pos σ !! int.val a = Some installedb ->
  disk_at_txn_id diskpos σ !! int.val a = Some b ->
  b ∈ installedb :: updates_since pos a σ.
Proof.
Admitted.

Theorem disk_at_txn_id_installed_to σ pos0 pos :
  disk_at_txn_id pos0 (@set _ _  log_state.installed_lb
      (fun _ (x2 : log_state.t) => x2) (λ _ : nat, pos) σ) =
  disk_at_txn_id pos0 σ.
Proof.
  destruct σ; auto.
Qed.

(* Specs *)

Lemma wal_update_durable (gh : gmap u64 heap_block) (σ : log_state.t) new_durable :
  forall a b hb,
  (σ.(log_state.durable_lb) ≤ new_durable ≤ length (log_state.updates σ))%nat ->
  (gh !! a = Some hb) ->
  (last_disk σ !! int.val a = Some b) ->
  ([∗ map] a1↦b0 ∈ gh, wal_heap_inv_addr σ a1 b0) -∗
   [∗ map] a1↦b0 ∈ gh, wal_heap_inv_addr
     (set log_state.durable_lb (λ _ : nat, new_durable) σ) a1 b0.
Proof.
  iIntros (a b hb) "% % % Hmap".
  destruct σ; simpl in *.
  rewrite /set /=.
  iDestruct (big_sepM_mono _ (wal_heap_inv_addr {|
                                  log_state.d := d;
                                  log_state.installed_lb := installed_lb;
                                  log_state.durable_lb := new_durable |}) with "Hmap") as "Hmap".
  2: iFrame.
  rewrite /wal_heap_inv_addr.
  iIntros; iPureIntro.
  destruct x; auto.
Qed.

Lemma wal_update_installed (gh : gmap u64 heap_block) (σ : log_state.t) new_installed :
  forall a b hb,
  (σ.(log_state.installed_lb) ≤ new_installed ≤ σ.(log_state.durable_lb))%nat ->
  (gh !! a = Some hb) ->
  (last_disk σ !! int.val a = Some b) ->
  ([∗ map] a1↦b0 ∈ gh, wal_heap_inv_addr σ a1 b0) -∗
   [∗ map] a1↦b0 ∈ gh, wal_heap_inv_addr
     (set log_state.installed_lb (λ _ : nat, new_installed) σ) a1 b0.
Proof.
  iIntros (a b hb) "% % % Hmap".
  destruct σ eqn:sigma; simpl in *.
  rewrite /set /=.
  iDestruct (big_sepM_mono _ (wal_heap_inv_addr {|
                                  log_state.d := d;
                                  log_state.installed_lb := new_installed;
                                  log_state.durable_lb := durable_lb |})
               with "Hmap") as "Hmap".
  2: iFrame.
  rewrite /wal_heap_inv_addr.
  iIntros; iPureIntro.
  destruct x; eauto.
  intuition.
  simpl in *.

  destruct a0.
  exists x.
  intuition.
  lia.
Qed.


Definition readmem_q γh (a : u64) (installed : Block) (bs : list Block) (res : option Block) : iProp Σ :=
  (
    match res with
    | Some resb =>
      mapsto (hG := γh) a 1 (HB installed bs) ∗
      ⌜ resb = latest_update installed bs ⌝
    | None =>
      mapsto (hG := γh) a 1 (HB (latest_update installed bs) nil)
    end
  )%I.

Theorem wal_heap_readmem N2 γh a (Q : option Block -> iProp Σ) :
  ( |={⊤ ∖ ↑N, ⊤ ∖ ↑N ∖ ↑N2}=> ∃ installed bs, mapsto (hG := γh) a 1 (HB installed bs) ∗
        ( ∀ mb, readmem_q γh a installed bs mb ={⊤ ∖ ↑N ∖ ↑N2, ⊤ ∖ ↑N}=∗ Q mb ) ) -∗
  ( ∀ σ σ' mb,
      ⌜wal_wf σ⌝ -∗
      ⌜relation.denote (log_read_cache a) σ σ' mb⌝ -∗
      ( (wal_heap_inv γh) σ ={⊤ ∖ ↑N}=∗ (wal_heap_inv γh) σ' ∗ Q mb ) ).
Proof.
  iIntros "Ha".
  iIntros (σ σ' mb) "% % Hinv".
  iDestruct "Hinv" as (gh) "[Hctx Hgh]".

  iMod "Ha" as (installed bs) "[Ha Hfupd]".
  iDestruct (gen_heap_valid with "Hctx Ha") as "%".
  iDestruct (big_sepM_lookup with "Hgh") as "%"; eauto.

  destruct H0.
  intuition.

  simpl in *; monad_inv.
  destruct b.
  - simpl in *; monad_inv.
    simpl in *; monad_inv.

    erewrite updates_since_to_last_disk in a1; eauto; try lia.
    simpl in *; monad_inv.

    iDestruct ("Hfupd" $! (Some (latest_update installed
                                    (updates_since x a σ))) with "[Ha]") as "Hfupd".
    { rewrite /readmem_q. iFrame. done. }
    iMod "Hfupd".

    iModIntro.
    iSplitL "Hctx Hgh".
    + iExists _; iFrame.
    + iFrame.

  - simpl in *; monad_inv.

    iMod (gen_heap_update _ _ _ (HB (latest_update installed (updates_since x a σ)) nil) with "Hctx Ha") as "[Hctx Ha]".
    iDestruct ("Hfupd" $! None with "[Ha]") as "Hfupd".
    {
      rewrite /readmem_q.
      iFrame.
    }
    iMod "Hfupd".
    iModIntro.
    iSplitL "Hctx Hgh".
    2: iFrame.

    iDestruct (wal_update_installed gh _ new_installed with "Hgh") as "Hgh"; eauto; try lia.
    + rewrite /set /=.
      intuition idtac.
      simpl in *.
      admit.
    + apply updates_since_to_last_disk; eauto; try lia.
    + iDestruct (big_sepM_insert_acc with "Hgh") as "[_ Hgh]"; eauto.
      iDestruct ("Hgh" $! (HB (latest_update installed (updates_since x a σ)) nil) with "[]") as "Hx".
      {
        rewrite /set /=.
        rewrite /wal_heap_inv.
        rewrite /wal_heap_inv_addr /=.
        iPureIntro; intros.
        simpl in H5.
        exists new_installed. intuition try lia.
        {
          rewrite <- updates_since_to_last_disk; eauto; try lia.
          rewrite no_updates_since_last_disk; auto.
          apply wal_wf_advance_installed_to; eauto; try lia.
          admit.
        }
        {
          rewrite no_updates_since_nil; auto.
          apply wal_wf_advance_installed_to; auto; try lia.
          admit.
        }
      }
      rewrite /wal_heap_inv.
      iExists _; iFrame.
Admitted.

Definition readinstalled_q γh (a : u64) (installed : Block) (bs : list Block) (res : Block) : iProp Σ :=
  (
    mapsto (hG := γh) a 1 (HB installed bs) ∗
    ⌜ res ∈ installed :: bs ⌝
  )%I.

Theorem wal_heap_readinstalled N2 γh a (Q : Block -> iProp Σ) :
  ( |={⊤ ∖ ↑N, ⊤ ∖ ↑N ∖ ↑N2}=> ∃ installed bs, mapsto (hG := γh) a 1 (HB installed bs) ∗
        ( ∀ b, readinstalled_q γh a installed bs b ={⊤ ∖ ↑N ∖ ↑N2, ⊤ ∖ ↑N}=∗ Q b ) ) -∗
  ( ∀ σ σ' b',
      ⌜wal_wf σ⌝ -∗
      ⌜relation.denote (log_read_installed a) σ σ' b'⌝ -∗
      ( (wal_heap_inv γh) σ ={⊤ ∖↑ N}=∗ (wal_heap_inv γh) σ' ∗ Q b' ) ).
Proof.
  iIntros "Ha".
  iIntros (σ σ' b') "% % Hinv".
  iDestruct "Hinv" as (gh) "[Hctx Hgh]".

  iMod "Ha" as (installed bs) "[Ha Hfupd]".
  iDestruct (gen_heap_valid with "Hctx Ha") as "%".
  iDestruct (big_sepM_lookup with "Hgh") as "%"; eauto.

  simpl in *; monad_inv.
  simpl in *; monad_inv.

  match goal with
  | H : context[unwrap ?x] |- _ => destruct x eqn:?
  end.
  2: simpl in *; monad_inv; done.
  simpl in *; monad_inv.

  iDestruct ("Hfupd" $! b with "[Ha]") as "Hfupd".
  { rewrite /readinstalled_q. iFrame.
    iPureIntro.
    destruct H0; intuition. subst.
    assert (b ∈ installed :: updates_since x a σ).
    {
      eapply updates_since_apply_upds.
      3: eauto.
      3: eauto.
      all: simpl; try lia.
    }

    inversion H6.
    { econstructor. }
    { econstructor.
      epose proof elem_of_subseteq. edestruct H11.
      apply H13 in H10; eauto.
    }
  }
  iMod "Hfupd".
  iModIntro.
  iFrame.

  destruct H0. intuition.
  iDestruct (wal_update_installed gh (set log_state.installed_lb (λ _, new_installed) σ) new_installed with "Hgh") as "Hgh".
  2: eauto.
  {
    rewrite /set.
    intuition.
    admit.
  }
  {
    apply updates_since_to_last_disk; eauto.
    (* { rewrite disk_at_txn_id_installed_to; eauto. } *)
    rewrite /set. lia.
  }

  iExists _. iFrame.
Admitted.

Definition memappend_pre γh (bs : list update.t) (olds : list (Block * list Block)) : iProp Σ :=
  [∗ list] _ ↦ u; old ∈ bs; olds,
    mapsto (hG := γh) u.(update.addr) 1 (HB (fst old) (snd old)).

Definition memappend_q γh (bs : list update.t) (olds : list (Block * list Block)) (pos : u64): iProp Σ :=
  [∗ list] _ ↦ u; old ∈ bs; olds,
    mapsto (hG := γh) u.(update.addr) 1 (HB (fst old) (snd old ++ [u.(update.b)])).

Fixpoint memappend_gh (gh : gmap u64 heap_block) bs olds :=
  match bs, olds with
  | b :: bs, old :: olds =>
    memappend_gh (<[b.(update.addr) := HB old.1 (old.2 ++ [b.(update.b)])]> gh) bs olds
  | _, _ => gh
  end.

Theorem memappend_pre_in_gh γh (gh : gmap u64 heap_block) bs olds :
  gen_heap_ctx gh -∗
  memappend_pre γh bs olds -∗
  ⌜ ∀ u i,
      bs !! i = Some u ->
      ∃ old, olds !! i = Some old ∧
             gh !! u.(update.addr) = Some (HB (fst old) (snd old)) ⌝.
Proof.
  iIntros "Hctx Hmem % % %".
  rewrite /memappend_pre //.
  iDestruct (big_sepL2_lookup_1_some with "Hmem") as %Hv; eauto.
  destruct Hv.
  iDestruct (big_sepL2_lookup_acc with "Hmem") as "[Hx Hmem]"; eauto.
  iDestruct (gen_heap_valid with "Hctx Hx") as %Hv.
  eauto.
Qed.

Lemma wal_heap_memappend_pre_to_q gh γh bs olds newpos :
  ( gen_heap_ctx gh ∗
    memappend_pre γh bs olds )
  ==∗
  ( gen_heap_ctx (memappend_gh gh bs olds) ∗
    memappend_q γh bs olds newpos ).
Proof.
  iIntros "(Hctx & Hpre)".
  iDestruct (big_sepL2_length with "Hpre") as %Hlen.

  iInduction (bs) as [|b] "Ibs" forall (gh olds Hlen).
  {
    iModIntro.
    rewrite /memappend_pre /memappend_q.
    destruct olds; simpl in *; try congruence.
    iFrame.
  }

  destruct olds; simpl in *; try congruence.
  iDestruct "Hpre" as "[Ha Hpre]".
  iDestruct (gen_heap_valid with "Hctx Ha") as "%".

  iMod (gen_heap_update _ _ _ (HB p.1 (p.2 ++ [b.(update.b)])) with "Hctx Ha") as "[Hctx Ha]".

  iDestruct ("Ibs" $! _ olds with "[] Hctx Hpre") as "Hx".
  { iPureIntro. lia. }

  iMod "Hx" as "[Hctx Hq]".
  iModIntro.
  iFrame.
Qed.

Theorem memappend_pre_nodup γh (bs : list update.t) olds :
  memappend_pre γh bs olds -∗ ⌜NoDup (map update.addr bs)⌝.
Proof.
  iIntros "Hpre".
  iInduction bs as [|] "Hi" forall (olds).
  - simpl. iPureIntro. constructor.
  - iDestruct (big_sepL2_length with "Hpre") as %Hlen.
    destruct olds; simpl in *; try congruence.
    iDestruct "Hpre" as "[Ha Hpre]".
    iDestruct ("Hi" with "Hpre") as "%".

    iAssert (⌜update.addr a ∉ fmap update.addr bs⌝)%I as "%".
    {
      iClear "Hi".
      clear H Hlen.
      iInduction bs as [|] "Hi" forall (olds).
      + simpl. iPureIntro. apply not_elem_of_nil.
      + iDestruct (big_sepL2_length with "Hpre") as %Hlen.
        destruct olds; simpl in *; try congruence.
        iDestruct "Hpre" as "[Ha0 Hpre]".
        iDestruct ("Hi" with "Ha Hpre") as "%".
        destruct (decide (a.(update.addr) = a0.(update.addr))).
        {
          rewrite e.
          iDestruct (mapsto_valid_2 with "Ha Ha0") as %Hd.
          exfalso. apply Hd. simpl. auto.
        }
        iPureIntro.
        simpl.
        apply not_elem_of_cons.
        auto.
    }
    iPureIntro.
    eapply NoDup_cons_2; eauto.
Qed.

(*
Theorem apply_upds_insert addr b bs d :
  addr ∉ fmap update.addr bs ->
  <[int.val addr:=b]> (apply_upds bs d) =
  apply_upds bs (<[int.val addr:=b]> d).
Proof.
  induction bs; eauto; simpl; intros.
  destruct a.
  apply not_elem_of_cons in H.
  simpl in *.
  intuition.
  rewrite insert_commute.
  { rewrite H; auto. }
  apply u64_val_ne.
  congruence.
Qed.
*)

Lemma memappend_gh_not_in_bs : ∀ bs olds gh a,
  a ∉ fmap update.addr bs ->
  memappend_gh gh bs olds !! a = gh !! a.
Proof.
  induction bs; simpl; intros; eauto.
  destruct olds; eauto.
  apply not_elem_of_cons in H; intuition idtac.
  rewrite IHbs; eauto.
  rewrite lookup_insert_ne; eauto.
Qed.

Lemma memappend_gh_olds : ∀ bs olds gh i u old,
  bs !! i = Some u ->
  olds !! i = Some old ->
  NoDup (map update.addr bs) ->
  memappend_gh gh bs olds !! u.(update.addr) = Some (HB (fst old) (snd old ++ [u.(update.b)])).
Proof.
  induction bs; intros.
  { rewrite lookup_nil in H. congruence. }
  destruct olds.
  { rewrite lookup_nil in H0. congruence. }
  destruct i.
  { simpl. intros.
    inversion H; clear H; subst.
    inversion H0; clear H0; subst.
    rewrite memappend_gh_not_in_bs.
    { rewrite lookup_insert; eauto. }
    inversion H1; eauto.
  }

  simpl in *. intros.
  inversion H1.
  erewrite IHbs; eauto.
Qed.

Lemma disk_at_txn_id_append σ (txn_id : nat) pos new :
  wal_wf σ ->
  (txn_id ≤ length σ.(log_state.txns))%nat ->
  disk_at_txn_id txn_id σ =
    disk_at_txn_id txn_id (set log_state.txns
                                 (λ upds, upds ++ [(pos,new)]) σ).
Proof.
  intros.
  rewrite /set //.
Admitted.

Lemma latest_update_app : ∀ l b0 b,
  latest_update b0 (l ++ [b]) = b.
Proof.
  induction l; simpl; eauto.
Qed.


Lemma last_cons A (l : list A):
  l ≠ [] -> forall a, last (a::l) = last l.
Proof.
  intros.
  induction l.
  - congruence.
  - destruct (decide (l = [])).
    + subst; auto.
    + simpl.
      f_equal.
Qed.

Lemma last_Some A (l : list A):
  l ≠ [] -> exists e, last l = Some e.
Proof.
  induction l.
  - intros. congruence.
  - intros.
    destruct (decide (l = [])).
    + subst; simpl.
      exists a; auto.
    + rewrite last_cons; auto.
Qed.

Theorem lastest_update_cons installed a:
  forall bs,
    latest_update installed (a :: bs) = latest_update a bs.
Proof.
  reflexivity.
Qed.

Lemma latest_update_last l:
  l ≠ [] ->
  forall b i, latest_update i l = b -> last l = Some b.
Proof.
  induction l.
  - intros.
    congruence.
  - intros.
    destruct (decide (l = [])).
    + subst. simpl; auto.
    + rewrite last_cons; auto.
      rewrite lastest_update_cons in H0; auto.
      specialize (IHl n b a).
      apply IHl; auto.
Qed.

Lemma latest_update_some l i:
  exists b, latest_update i l = b.
Proof.
  generalize dependent i.
  induction l.
  - intros.
    exists i.
    simpl; auto.
  - intros.
    rewrite lastest_update_cons //.
Qed.

Lemma latest_update_last_eq i l0 l1 :
  last l0 = last l1 ->
  latest_update i l0 = latest_update i l1.
Proof.
  intros.
  destruct (decide (l0 = [])); auto.
  {
    destruct (decide (l1 = [])); auto.
    1: subst; simpl in *; auto.
    subst; simpl in *.
    apply last_Some in n.
    destruct n.
    rewrite H0 in H.
    congruence.
  }
  destruct (decide (l1 = [])); auto.
  {
    subst; simpl in *; auto.
    apply last_Some in n.
    destruct n.
    rewrite H0 in H.
    congruence.
  }
  assert (exists b, latest_update i l0 = b).
  1: apply latest_update_some.
  assert (exists b, latest_update i l1 = b).
  1: apply latest_update_some.
  destruct H0.
  destruct H1.
  apply latest_update_last in H0 as H0'; auto.
  apply latest_update_last in H1 as H1'; auto.
  subst.
  rewrite H0' in H.
  rewrite H1' in H.
  inversion H; auto.
Qed.

Lemma updates_for_addr_notin : ∀ bs a,
  a ∉ fmap update.addr bs ->
  updates_for_addr a bs = nil.
Proof.
  induction bs; intros; eauto.
  rewrite fmap_cons in H.
  apply not_elem_of_cons in H; destruct H.
  erewrite <- IHbs; eauto.
  destruct a; rewrite /updates_for_addr filter_cons /=; simpl in *.
  destruct (decide (addr = a0)); congruence.
Qed.

Theorem updates_for_addr_in : ∀ bs u i,
  bs !! i = Some u ->
  NoDup (fmap update.addr bs) ->
  updates_for_addr u.(update.addr) bs = [u.(update.b)].
Proof.
  induction bs; intros.
  { rewrite lookup_nil in H; congruence. }
  destruct i; simpl in *.
  { inversion H; clear H; subst.
    rewrite /updates_for_addr filter_cons /=.
    destruct (decide (u.(update.addr) = u.(update.addr))); try congruence.
    inversion H0.
    apply updates_for_addr_notin in H2.
    rewrite /updates_for_addr in H2.
    rewrite fmap_cons.
    rewrite H2; eauto.
  }
  inversion H0; subst.
  erewrite <- IHbs; eauto.
  rewrite /updates_for_addr filter_cons /=.
  destruct (decide (a.(update.addr) = u.(update.addr))); eauto.
  exfalso.
  apply H3. rewrite e.
  eapply elem_of_list_lookup.
  eexists.
  rewrite list_lookup_fmap.
  erewrite H; eauto.
Qed.

Theorem latest_update_take_some bs v:
  forall installed (pos: nat),
    (installed :: bs) !! pos = Some v ->
    latest_update installed (take pos bs) = v.
Proof.
  induction bs.
  - intros.
    rewrite firstn_nil.
    simpl.
    assert(pos = 0%nat).
    {
      apply lookup_lt_Some in H.
      simpl in *.
      word.
    }
    rewrite H0 in H.
    simpl in *.
    inversion H; auto.
  - intros.
    destruct (decide (pos = 0%nat)).
    + rewrite e in H; simpl in *.
      inversion H; auto.
      rewrite e; simpl; auto.
    +
      assert (exists (pos':nat), pos = S pos').
      {
        exists (pred pos). lia.
      }
      destruct H0 as [pos' H0].
      rewrite H0.
      rewrite firstn_cons.
      destruct (decide ((take pos' bs) = [])).
      ++ simpl.
         specialize (IHbs a pos').
         apply IHbs.
         rewrite lookup_cons_ne_0 in H; auto.
         rewrite H0 in H; simpl in *; auto.
      ++ rewrite lastest_update_cons; auto.
         {
           specialize (IHbs a pos').
           apply IHbs.
           rewrite lookup_cons_ne_0 in H; auto.
           rewrite H0 in H; simpl in *; auto.
         }
Qed.

Theorem wal_heap_memappend N2 γh bs (Q : u64 -> iProp Σ) :
  ( |={⊤ ∖ ↑N, ⊤ ∖ ↑N ∖ ↑N2}=> ∃ olds, memappend_pre γh bs olds ∗
        ( ∀ pos, memappend_q γh bs olds pos ={⊤ ∖ ↑N ∖ ↑N2, ⊤ ∖ ↑N}=∗ Q pos ) ) -∗
  ( ∀ σ σ' pos,
      ⌜wal_wf σ⌝ -∗
      ⌜relation.denote (log_mem_append bs) σ σ' pos⌝ -∗
      ( (wal_heap_inv γh) σ ={⊤ ∖↑ N}=∗ (wal_heap_inv γh) σ' ∗ Q pos ) ).
Proof using gen_heapPreG0.
  iIntros "Hpre".
  iIntros (σ σ' pos) "% % Hinv".
  iDestruct "Hinv" as (gh) "[Hctx Hgh]".

  simpl in *; monad_inv.
  simpl in *.

  iMod "Hpre" as (olds) "[Hpre Hfupd]".
  iDestruct (memappend_pre_nodup with "Hpre") as %Hnodup.
  iDestruct (big_sepL2_length with "Hpre") as %Hlen.
  iDestruct (memappend_pre_in_gh with "Hctx Hpre") as %Hbs_in_gh.

  iMod (wal_heap_memappend_pre_to_q with "[$Hctx $Hpre]") as "[Hctx Hq]".
  (*
  iSpecialize ("Hfupd" $! (length (stable_upds σ ++ new))).
  iDestruct ("Hfupd" with "Hq") as "Hfupd".
  iMod "Hfupd".
  iModIntro.
  iFrame.

  iExists _. iFrame.
  intuition.

  iDestruct (big_sepM_forall with "Hgh") as %Hgh.
  iApply big_sepM_forall.

  iIntros (k b Hkb).
  destruct b.
  iPureIntro.
  clear Q.
  simpl.
  specialize (Hgh k).

  destruct (decide (k ∈ fmap update.addr bs)).
  - eapply elem_of_list_fmap in e as ex.
    destruct ex. intuition. subst.
    apply elem_of_list_lookup in H4; destruct H4.
    edestruct Hbs_in_gh; eauto; intuition.
    specialize (Hgh _ H5). simpl in *.
    destruct Hgh as [pos Hgh].
    exists pos.

    pose proof Hkb as Hkb'.
    erewrite memappend_gh_olds in Hkb'; eauto.
    inversion Hkb'; clear Hkb'; subst.
    destruct x2; simpl in *.

    intuition.

    {
      rewrite -disk_at_txn_id_trans.
      rewrite -disk_at_txn_id_append; eauto.
    }

    {
      rewrite -updates_since_trans.
      etransitivity; first by apply updates_since_updates.
      erewrite updates_for_addr_in; eauto.
      set_solver.
    }

    {
      rewrite -updates_since_trans.
      rewrite latest_update_app.
      erewrite latest_update_last_eq.
      2: {
        eapply updates_since_absorb; eauto.
      }
      erewrite updates_for_addr_in; eauto.
      rewrite latest_update_app; eauto.
    }

  - rewrite memappend_gh_not_in_bs in Hkb; eauto.
    specialize (Hgh _ Hkb).
    simpl in *.

    destruct Hgh as [pos Hgh].
    exists pos.
    intuition.

    {
      rewrite -disk_at_txn_id_trans.
      rewrite -disk_at_txn_id_append; eauto.
    }

    {
      etransitivity.
      2: eassumption.
      rewrite -updates_since_trans.

      etransitivity; first by apply updates_since_updates.
      erewrite updates_for_addr_notin; eauto.
      set_solver.
    }

    {
      rewrite H6.
      rewrite -updates_since_trans.
      etransitivity.
      2: erewrite latest_update_last_eq; first reflexivity.
      2: apply updates_since_absorb; eauto.
      rewrite updates_for_addr_notin; eauto.
      rewrite app_nil_r; eauto.
    }
Qed.
*)
Admitted.

End heap.
