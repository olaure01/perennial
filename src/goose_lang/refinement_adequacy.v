From iris.proofmode Require Import tactics.
From iris.algebra Require Import auth.
From iris.base_logic.lib Require Import proph_map.
From iris.program_logic Require Export weakestpre adequacy.
From Perennial.goose_lang Require Import proofmode notation.
From Perennial.program_logic Require Import recovery_weakestpre recovery_adequacy spec_assert.
From Perennial.goose_lang Require Import typing adequacy refinement.
From Perennial.goose_lang Require Export recovery_adequacy spec_assert.

Class spec_ffi_interp_adequacy `{spec_ffi: @spec_ffi_interp ffi} `{EXT: !spec_ext_semantics ext ffi} :=
  { spec_ffi_interp_adequacy_field : @ffi_interp_adequacy _ (spec_ffi_interp_field)
                                                          (spec_ext_op_field)
                                                          (spec_ext_semantics_field) }.

Class refinement_heapPreG `{ext: spec_ext_op} `{@spec_ffi_interp_adequacy ffi spec_ffi ext EXT} Σ := HeapPreG {
  refinement_heap_preG_heap :> gen_heapPreG loc (nonAtomic (@val spec_ext_op_field)) Σ;
  refinement_heap_preG_ffi : @ffi_preG (@spec_ffi_model_field ffi)
                                       (@spec_ffi_interp_field _ spec_ffi)
                                       _ _ (spec_ffi_interp_adequacy_field) Σ;
  refinement_heap_preG_trace :> trace_preG Σ;
}.

Section refinement.
Context {ext: ext_op}.
Context {ffi: ffi_model}.
Context {ffi_semantics: ext_semantics ext ffi}.
Context `{interp: !ffi_interp ffi}.
Context `{interp_adeq: !ffi_interp_adequacy}.

Context {spec_ext: spec_ext_op}.
Context {spec_ffi: spec_ffi_model}.
Context {spec_ffi_semantics: spec_ext_semantics spec_ext spec_ffi}.
Context `{spec_interp: @spec_ffi_interp spec_ffi}.
Context `{spec_adeq: !spec_ffi_interp_adequacy}.

Context `{Hhpre: @heapPreG ext ffi ffi_semantics interp _ Σ}.
Context `{Hcpre: @cfgPreG spec_lang Σ}.
Context `{Hrpre: @refinement_heapPreG spec_ext spec_ffi spec_interp _ spec_adeq Σ}.

Existing Instances spec_ffi_model_field spec_ext_op_field spec_ext_semantics_field spec_ffi_interp_field.

Lemma goose_spec_init {hG: heapG Σ} r tp σ tr or:
  σ.(trace) = tr →
  σ.(oracle) = or →
  crash_safe (CS := spec_crash_lang) r (tp, σ) →
  (trace_frag tr -∗ oracle_frag or -∗
   |={⊤}=> ∃ _ : refinement_heapG Σ, spec_ctx' r (tp, σ) ∗ source_pool_map (tpool_to_map tp)
                                               ∗ trace_ctx)%I.
Proof.
  iIntros (?? Hsafe) "Htr Hor".
  iMod (source_cfg_init r tp σ) as (Hcfg) "(Hsource_ctx&Hpool&Hstate)"; first done.
  iMod (gen_heap_init σ.(heap)) as (Hrheap) "Hrh".
  iMod (ffi_init _ (refinement_heap_preG_ffi) σ.(world)) as (HffiG) "Hrw".
  iMod (trace_init σ.(trace) σ.(oracle)) as (HtraceG) "(?&Htr'&?&Hor')".
  set (HrhG := (refinement_HeapG _ HffiG HtraceG Hcfg Hrheap)).
  iExists HrhG.
  rewrite /spec_ctx'. iFrame.
  iMod (inv_alloc (spec_stateN) _
                  (∃ σ0 : language.state heap_lang, (source_state σ0 ∗ spec_assert.spec_interp σ0))
       with "[-Htr' Hor' Htr Hor]")%I as "$".
  { iNext. iExists _. iFrame. }
  rewrite /trace_ctx.
  iMod (inv_alloc (spec_traceN) _ trace_inv with "[-]") as "$".
  { iNext. subst. rewrite /trace_inv. iExists _, _, _, _. iFrame; eauto. }
  done.
Qed.

Lemma trace_inv_open {hG: heapG Σ} {hrG: refinement_heapG Σ}  rs es σs σ:
  spec_ctx' rs ([es], σs) -∗
  trace_ctx -∗
  trace_auth (trace σ) -∗
  oracle_auth (oracle σ) -∗
  |={⊤,∅}=> ⌜∃ (t2s : list expr) (σ2s : state) (stats : status),
            erased_rsteps (CS := spec_crash_lang) rs ([es], σs) (t2s, σ2s) stats ∧ trace σ2s = trace σ⌝.
Proof.
  iIntros "Hspec Htrace Htrace_auth Horacle_auth".
  rewrite /spec_ctx'.
  iDestruct "Hspec" as "(Hsource&Hspec_state)".
  iInv "Hsource" as "Hsource_open" "_".
  iInv "Hspec_state" as "Hspec_state_open" "_".
  iInv "Htrace" as ">Htrace_open" "_".
  rewrite /source_inv.
  iDestruct "Hsource_open" as (???) "(>Hsource_auth&>(%&%))".
  iDestruct "Hspec_state_open" as (?) "(>Hsource_state&Hspec_interp)".
  iDestruct "Hspec_interp" as "(?&?&>Hspec_trace_auth&>Hspec_oracle_auth)".
  rewrite /trace_inv.
  iDestruct "Htrace_open" as (???? ??) "(Htrace_frag&Hspec_trace_frag&Horacle_frag&Htspec_oracle_frag)".
  iDestruct (source_state_reconcile with "[$] [$]") as %Heq0.
  iDestruct (trace_agree with "Htrace_auth [$]") as %Heq1.
  iDestruct (trace_agree with "Hspec_trace_auth [$]") as %Heq2.
  iDestruct (oracle_agree with "Horacle_auth [$]") as %Heq3.
  iDestruct (oracle_agree with "Hspec_oracle_auth [$]") as %Heq4.
  iApply fupd_mask_weaken; first by set_solver+.
  iExists _, _, _; iPureIntro; split.
  { eauto. }
  { subst. congruence. }
Qed.

Theorem heap_recv_refinement_adequacy `{crashPreG Σ} k es e rs r σs σ φ φr Φinv :
  σ.(trace) = σs.(trace) →
  σ.(oracle) = σs.(oracle) →
  (∀ `{Hheap : !heapG Σ} `{Hc: !crashG Σ} {Href: refinement_heapG Σ} Hinv t,
     (|={⊤}=>
       (spec_ctx' rs ([es], σs) -∗
        trace_ctx -∗
       □ (∀ Hi t, Φinv Hi t -∗
                       let _ := heap_update _ Hheap Hi (@pbundleT _ _ t) in
                       ∃ Href', spec_ctx' (hR := Href') rs ([es], σs) ∗ trace_ctx (hR := Href')) ∗
        ((O ⤇ es) -∗ wpr NotStuck k Hinv Hc t ⊤ e r (λ v, ⌜φ v⌝) Φinv (λ _ _ v, ⌜φr v⌝))))%I) →
  trace_refines e r σ es rs σs.
Proof.
  intros ?? Hwp Hsafe.
  cut (recv_adequate (CS := heap_crash_lang) NotStuck e r σ (λ v _, φ v) (λ v _, φr v)
                     (λ σ2,
                      ∃ t2s σ2s stats,
                        erased_rsteps (CS:= spec_crash_lang) rs ([es], σs) (t2s, σ2s) stats ∧
                        σ2s.(trace) = σ2.(trace))); eauto.
  { intros Hrecv.
    split.
    - intros ?????. eapply recv_adequate_not_stuck; eauto.
    - intros tr Hobs. destruct Hobs as (?&?&?&Hexec&Htr).
      eapply (recv_adequate_inv _ _ _ _ _ _ _ Hrecv) in Hexec.
      subst. destruct Hexec as (t2s&σ2s&?&Hexecs&Htrs).
      exists (trace σ2s); split; eauto.
      * do 3 eexists; eauto.
      * rewrite Htrs. by exists []; rewrite app_nil_r.
  }
  eapply (wp_recv_adequacy_inv _ _ _ heap_namesO _ _).
  iIntros (???) "".
  iMod (gen_heap_init σ.(heap)) as (?) "Hh".
  iMod (proph_map_init κs σ.(used_proph_id)) as (?) "Hp".
  iMod (ffi_init _ _ σ.(world)) as (HffiG) "Hw".
  iMod (trace_init σ.(trace) σ.(oracle)) as (HtraceG) "(Htr&Htrfrag&Hor&Hofrag)".
  set (hG := (HeapG _ _ HffiG _ _ HtraceG)).
  set (hnames := heap_get_names _ (HeapG _ _ HffiG _ _ HtraceG)).
  iExists ({| pbundleT := hnames |}).
  iExists
    (λ t σ κs, let _ := heap_update_names Σ hG (@pbundleT _ _ t) in
               state_interp σ κs O)%I,
    (λ t _, True%I).
  iExists (λ _ _, eq_refl).
  iMod (goose_spec_init with "[$] [$]") as (HrG) "(#Hspec&Hpool&#Htrace)"; try (by symmetry); eauto.
  iMod (Hwp hG Hc HrG Hinv {| pbundleT := hnames |} with "[$] [$]") as "(#H1&Hwp)".
  iDestruct (source_pool_singleton with "Hpool") as "Hpool".
  iSpecialize ("Hwp" with "[$]"). iFrame.
  rewrite /heapG_ffiG//= ffi_get_update. iFrame.
  iModIntro. iSplit.
  - iAlways. iIntros (??) "(Hheap_ctx&Hproh_ctx&Hffi_ctx&Htrace_auth&Horacle_auth)".
    iApply (trace_inv_open with "[$] [$] [$] [$]").
  - iAlways. iIntros (Hi' Hnames') "Hinv".
    iClear "Hspec Htrace".
    iDestruct ("H1" with "[$]") as (?) "(#Hspec_ctx&#Htrace_ctx)".
    iClear "H1". iAlways.
    iIntros (??) "(Hheap_ctx&Hproh_ctx&Hffi_ctx&Htrace_auth&Horacle_auth)".
    iApply (@trace_inv_open (heap_update Σ hG _ (@pbundleT _ _ Hnames')) with "[$] [$] [$] [$]").
Qed.

End refinement.