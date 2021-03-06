From Perennial.program_proof Require Import proof_prelude.
From Goose.github_com.mit_pdos.goose_nfsd Require Import util.

Section heap.
Context `{!heapG Σ}.
Context `{!crashG Σ}.
Implicit Types (v:val).
Implicit Types (stk:stuckness) (E: coPset).

Theorem wp_Min_l stk E (n m: u64) Φ :
  int.val n <= int.val m ->
  Φ #n -∗ WP (Min #n #m) @ stk; E {{ Φ }}.
Proof.
  iIntros (Hlt) "HΦ".
  wp_call.
  wp_if_destruct.
  - iFrame.
  - assert (int.val n = int.val m) by word.
    apply word.unsigned_inj in H; subst.
    iFrame.
Qed.

Theorem wp_Min_r stk E (n m: u64) Φ :
  int.val n >= int.val m ->
  Φ #m -∗ WP (Min #n #m) @ stk; E {{ Φ }}.
Proof.
  iIntros (Hlt) "HΦ".
  wp_call.
  wp_if_destruct.
  - assert (int.val n = int.val m) by word.
    apply word.unsigned_inj in H; subst.
    iFrame.
  - iFrame.
Qed.

Theorem wp_DPrintf stk E (level: u64) (msg arg: val) :
  {{{ True }}}
    util.DPrintf #level msg arg @ stk; E
  {{{ RET #(); True }}}.
Proof.
  iIntros (Φ) "_ HΦ".
  iSpecialize ("HΦ" with "[//]").
  wp_call.
  wp_if_destruct; auto.
Qed.

Lemma mod_add_modulus a k :
  k ≠ 0 ->
  a `mod` k = (a + k) `mod` k.
Proof.
  intros.
  rewrite -> Z.add_mod by auto.
  rewrite -> Z.mod_same by auto.
  rewrite Z.add_0_r.
  rewrite -> Z.mod_mod by auto.
  auto.
Qed.

Lemma mod_sub_modulus a k :
  k ≠ 0 ->
  a `mod` k = (a - k) `mod` k.
Proof.
  intros.
  rewrite -> Zminus_mod by auto.
  rewrite -> Z.mod_same by auto.
  rewrite Z.sub_0_r.
  rewrite -> Z.mod_mod by auto.
  auto.
Qed.

Theorem sum_overflow_check (x y: u64) :
  int.val (word.add x y) < int.val x <-> int.val x + int.val y >= 2^64.
Proof.
  split; intros.
  - revert H; word_cleanup; intros.
    rewrite /word.wrap in H1.
    destruct (decide (int.val x + int.val y >= 2^64)); [ auto | exfalso ].
    rewrite -> Zmod_small in H1 by lia.
    lia.
  - word_cleanup.
    rewrite /word.wrap.
    rewrite -> mod_sub_modulus by lia.
    rewrite -> Zmod_small by lia.
    lia.
Qed.

Theorem wp_SumOverflows stk E (x y: u64) :
  {{{ True }}}
    util.SumOverflows #x #y @ stk; E
  {{{ (ok: bool), RET #ok; ⌜ok = bool_decide (int.val x + int.val y >= 2^64)⌝ }}}.
Proof.
  iIntros (Φ) "_ HΦ".
  wp_call.
  iApply "HΦ".
  iPureIntro.
  apply bool_decide_iff, sum_overflow_check.
Qed.

End heap.
