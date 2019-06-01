From stdpp Require Import base countable.
From Tactical Require Import ProofAutomation.

From RecordUpdate Require Import RecordUpdate RecordSet.
From Transitions Require Import Relations.

From Armada Require Import Helpers.RecordZoom.
From Armada Require Import Spec.Proc.
From Armada Require Import Spec.GreedyProc.
From Armada Require Import Spec.InjectOp.
From Armada Require Import Spec.SemanticsHelpers.
From Armada Require Import Spec.LockDefs.
From Armada Require Import Spec.Layer.
From Armada.Goose Require Import base Machine Filesys Heap GoZeroValues GoLayer Globals.
(* From Armada.Goose.Examples Require Import UnitTests. *)

Instance goModel : GoModel :=
  { byte := unit;
    byte0 := tt;

    uint64_to_string n := ""%string;
    ascii_to_byte a := tt;
    byte_to_ascii b := Ascii.zero;

    uint64_to_le u := [tt];
    uint64_from_le bs := None;

    File := unit;
    nilFile := tt;

    Ptr ty := nat;
    nullptr ty := 0;
    }.

Declare Instance goModelWf : GoModelWf goModel.
Notation G := (slice.t LockRef).

Notation es := (@Proc.State Go.State).
Notation gs := Go.State.
Notation fs := FS.State.
Notation ds := Data.State.
Notation gb := (@Globals.State G).

Module RTerm.
  Inductive t : Type -> Type -> Type -> Type :=
  (* atomic operations *)
  | Reads T : (ds -> T) -> t ds ds T
  | Puts : (fs -> fs) -> t fs fs unit
  | ReadSome T : (ds -> option T) -> t ds ds T
  | ReadNone T : (ds -> option T) -> t ds ds unit
  | ReadsGB T : (gb -> T) -> t gb gb T
  | ReadSomeGB T : (gb -> option T) -> t gb gb T

  | AllocPtr ty : Data.ptrRawModel ty -> t ds ds (goModel.(@Ptr) ty)
  | UpdAllocs ty : Ptr ty -> Data.ptrModel ty -> t ds ds unit
  | DelAllocs ty : Ptr ty -> t ds ds unit

  (* sequencing *)
  | Pure A T : T -> t A A T
  | Ret T : T -> t es es T
  | BindES T1 T2 : t es es T1 -> (T1 -> t es es T2) -> t es es T2
  | AndThenGS T1 T2 : t gs gs T1 -> (T1 -> t gs gs T2) -> t gs gs T2
  | AndThenFS T1 T2 : t fs fs T1 -> (T1 -> t fs fs T2) -> t fs fs T2
  | AndThenDS T1 T2 : t ds ds T1 -> (T1 -> t ds ds T2) -> t ds ds T2
  | AndThenGB T1 T2 : t gb gb T1 -> (T1 -> t gb gb T2) -> t gb gb T2
  | BindStarES T : (T -> t es es T) -> T -> t es es T

  (* zooms *)
  | CallGS T : t gs gs T -> t es es T
  | ZoomFS T : t fs fs T -> t gs gs T
  | ZoomDS T : t ds ds T -> t fs fs T
  | ZoomGB T : t gb gb T -> t gs gs T
  | FstLiftES T : t nat nat T -> t es es T

  | NAMatch N A B T (na: NonAtomicArgs N) : t A B unit -> (N -> t A B T) -> t A B (retT na T)

  | Error A B T : t A B T
  | NotImpl A B T (r: relation A B T) : t A B T
  .
End RTerm.

Check FS.na_match.

Inductive Output B T : Type :=
| Success (b: B) (t: T) 
| Error
| NotImpl
.

Arguments Success {_ _}.
Arguments Error {_ _}.
Arguments NotImpl {_ _}.

Definition ptrMap := nat.
Definition ptrMap_null : ptrMap := 1.

Fixpoint rtermDenote A B T (r: RTerm.t A B T) : relation A B T :=
  match r with
  | RTerm.Reads f => reads f
  | RTerm.ReadSome f => readSome f
  | RTerm.ReadsGB f => reads f
  | RTerm.ReadSomeGB f => readSome f
  | RTerm.ReadNone f => readNone f
  | RTerm.Puts f => puts f
  | RTerm.AllocPtr _ prm => Data.allocPtr _ prm
  | RTerm.UpdAllocs p pm => Data.updAllocs p pm
  | RTerm.DelAllocs  p => Data.delAllocs p

  | RTerm.Pure A o0 => pure o0
  | RTerm.Ret x => pure x
  | RTerm.BindES r1 f => and_then (rtermDenote r1) (fun x => (rtermDenote (f x)))
  | RTerm.AndThenGS r1 f => and_then (rtermDenote r1) (fun x => (rtermDenote (f x)))
  | RTerm.AndThenFS r1 f => and_then (rtermDenote r1) (fun x => (rtermDenote (f x)))
  | RTerm.AndThenDS r1 f => and_then (rtermDenote r1) (fun x => (rtermDenote (f x)))
  | RTerm.AndThenGB r1 f => and_then (rtermDenote r1) (fun x => (rtermDenote (f x)))
  | RTerm.BindStarES rf o => bind_star (fun x => (rtermDenote (rf x))) o

  | RTerm.CallGS r => snd_lift (rtermDenote r)
  | RTerm.ZoomFS r => _zoom Go.fs (rtermDenote r)
  | RTerm.ZoomDS r => _zoom FS.heap (rtermDenote r)
  | RTerm.ZoomGB r => _zoom Go.maillocks (rtermDenote r)
  | RTerm.FstLiftES r => fst_lift (rtermDenote r)

  | RTerm.NAMatch na rBegin rFinish => FS.na_match na (rtermDenote rBegin) (fun a => rtermDenote (rFinish a))

  | RTerm.Error _ _ _ => error
  | RTerm.NotImpl r => r
  end.

Ltac refl' RetB RetT e :=
  match eval simpl in e with
  | fun x : ?T => @reads ds ?T0 (@?f x) =>
    constr: (fun x => RTerm.Reads (f x))
  | fun x : ?T => @readSome ds ?T0 (@?f x) =>
    constr: (fun x => RTerm.ReadSome (f x))
  | fun x : ?T => @reads ?s ?T0 (@?f x) =>
    constr: (fun x => RTerm.ReadsGB (f x))
  | fun x : ?T => @readSome ?s ?T0 (@?f x) =>
    constr: (fun x => RTerm.ReadSomeGB (f x))
  | fun x : ?T => @readNone ?A ?T0 (@?f x) =>
    constr: (fun x => RTerm.ReadNone (f x))
  | fun x : ?T => @puts fs (@?f x) =>
    constr: (fun x => RTerm.Puts (f x))
              
  | fun x: ?T => @Data.allocPtr _ _ (@?ty x) (@?prm x) =>
    constr:(fun x => @RTerm.AllocPtr (ty x) (prm x))
  | fun x: ?T => @Data.updAllocs _ _ ?ty ?p ?pm =>
    constr: (fun x => RTerm.UpdAllocs ty p pm)
  | fun x: ?T => @Data.delAllocs _ _ ?ty ?p =>
    constr: (fun x => RTerm.DelAllocs ty p)

  | fun x : ?T => @pure ?A _ (@?E x) =>
    constr: (fun x => RTerm.Ret es (E x))
  | fun x : ?T => @pure ?A _ (@?E x) =>
    constr: (fun x => RTerm.Pure A (E x))

  | fun x: ?T => @and_then ?A ?B ?C ?T1 ?T2 (@?r1 x) (fun (y: ?T1) => (@?r2 x y)) =>
    let f1 := refl' B T1 r1 in
    let f2 := refl' C T2 (fun (p: T * T1) => (r2 (fst p) (snd p))) in
    constr: (fun x => RTerm.BindES (f1 x) (fun y => f2 (x, y)))
  | fun x: ?T => @and_then gs gs gs ?T1 ?T2 (@?r1 x) (fun (y: ?T1) => (@?r2 x y)) =>
    let f1 := refl' gs T1 r1 in
    let f2 := refl' gs T2 (fun (p: T * T1) => (r2 (fst p) (snd p))) in
    constr: (fun x => RTerm.AndThenGS (f1 x) (fun y => f2 (x, y)))
  | fun x: ?T => @and_then fs fs fs ?T1 ?T2 (@?r1 x) (fun (y: ?T1) => (@?r2 x y)) =>
    let f1 := refl' fs T1 r1 in
    let f2 := refl' fs T2 (fun (p: T * T1) => (r2 (fst p) (snd p))) in
    constr: (fun x => RTerm.AndThenFS (f1 x) (fun y => f2 (x, y)))
  | fun x: ?T => @and_then ds ds ds ?T1 ?T2 (@?r1 x) (fun (y: ?T1) => (@?r2 x y)) =>
    let f1 := refl' ds T1 r1 in
    let f2 := refl' ds T2 (fun (p: T * T1) => (r2 (fst p) (snd p))) in
    constr: (fun x => RTerm.AndThenDS (f1 x) (fun y => f2 (x, y)))
  | fun x: ?T => @and_then ?A ?B ?C ?T1 ?T2 (@?r1 x) (fun (y: ?T1) => (@?r2 x y)) =>
    let f1 := refl' B T1 r1 in
    let f2 := refl' C T2 (fun (p: T * T1) => (r2 (fst p) (snd p))) in
    constr: (fun x => RTerm.AndThenGB (f1 x) (fun y => f2 (x, y)))
  | fun x: ?T => @bind_star ?A ?T1 (@?rf x) (@?o x) =>
    let f := refl' A T1 (fun (p: T * T1) => (rf (fst p) (snd p))) in
    constr: (fun x => RTerm.BindStarES (fun y => f (x, y)) (o x))

  | fun x: ?T => @snd_lift ?A1 ?A2 ?B ?T1 (@?r x) =>
    let f := refl' A2 T1 r in
    constr: (fun x => RTerm.CallGS (f x))
  | (fun x: ?T => @_zoom gs fs Go.fs _ ?T1 (@?r1 x)) =>
    let f := refl' fs T1 r1 in
    constr: (fun x: T => RTerm.ZoomFS (f x))
  | (fun x: ?T => @_zoom fs ds FS.heap _ ?T1 (@?r1 x)) =>
    let f := refl' ds T1 r1 in
    constr: (fun x: T => RTerm.ZoomDS (f x))
  | (fun x: ?T => @_zoom ?s1 ?s2 Go.maillocks _ ?T1 (@?r1 x)) =>
    let f := refl' s2 T1 r1 in
    constr: (fun x: T => RTerm.ZoomGB (f x))
  | fun x: ?T => @fst_lift ?A1 ?A2 ?B ?T1 (@?r x) =>
    let f := refl' A2 T1 r in
    constr: (fun x => RTerm.FstLiftES (f x))

  | fun x : ?T => (match ?r with (a, b) =>
                              @FS.na_match ?N fs fs ?T1 ?na (@?rBegin a b x) (@?rFinish a b x)
                end) =>
    let fBegin := refl' fs unit (fun p => (rBegin (fst p) (fst (snd p)) (snd (snd p)))) in
    idtac fBegin;
    let fFinish := refl' fs T1 (fun (p : (T * (_ * (_ * N)))) => (rFinish (fst p) (fst (snd p)) (fst (snd (snd p))) (snd (snd (snd p))))) in
                         constr: (fun x => match r with (a, b) =>
                                                     RTerm.NAMatch na
                                                                   (fBegin (a, (b, x)))
                                                                   (fun n => (fFinish (a, (b, (x, n)))))
                                        end)

  | fun x : ?T => (match ?r with (a, b) => (@?s a b x) end) =>
    (* The return type isn't necessarily unit, but Coq doesn't seem to care *)
    let f := refl' fs unit (fun p => (s (fst p) (fst (snd p)) (snd (snd p)))) in
    constr: (fun x => match r with (a, b) => (f (a, (b, x))) end)

  | fun x : ?T => (match ?r with (a, b) => (@?s a b x) end) =>
    let f := refl' gs unit (fun p => (s (fst p) (fst (snd p)) (snd (snd p)))) in
    constr: (fun x => match r with (a, b) => (f (a, (b, x))) end)

  | fun x : ?T => (match ?r with (FinishArgs _) => (@?s1 x) | Begin => (@?s2 x) end) =>
    let f1 := refl' fs unit s1 in
    let f2 := refl' fs unit s2 in
    constr: (fun x => match r with (FinishArgs _) => (f1 x) | Begin => (f2 x) end)

  (* can't use state types gb or es because of "bound to a notation that
     does not denote a reference" error *)
  | fun x : ?T => (match ?r with (FinishArgs _) => (@?s1 x) | Begin => (@?s2 x) end) =>
    let f1 := refl' _ unit s1 in
    let f2 := refl' _ unit s2 in
    constr: (fun x => match r with (FinishArgs _) => (f1 x) | Begin => (f2 x) end)

  | fun x : ?T => @FS.na_match ?N ?A ?B ?T1 ?na (@?rBegin x) (@?rFinish x) =>
    let fBegin := refl' B unit rBegin in
    let fFinish := refl' B T1 (fun (p : (T * N)%type) => (rFinish (fst p) (snd p))) in
    let nafun := constr: (fun x => RTerm.NAMatch na (fBegin x) (fun a => fFinish (x, a))) in idtac nafun;
    constr: (fun x => RTerm.NAMatch na (fBegin x) (fun a => fFinish (x, a)))

  | fun x : ?T => @error ?A ?B ?T0 =>
    constr: (fun x => RTerm.Error A B T0)
  | fun x : ?T => @?E x =>
    constr: (fun x => RTerm.NotImpl (E x))
   end.

Check @FS.na_match.
Check RTerm.NAMatch.

Ltac refl e :=
  lazymatch type of e with
  | @relation _ ?B ?T =>                        
    let t := refl' B T constr:(fun _ : unit => e) in
    let t' := (eval cbn beta in (t tt)) in
    constr:(t')
  end.

Ltac reflop_fs o :=
  let t := eval simpl in (Go.step (FilesysOp o)) in
      let t' := eval cbv [set] in t in (* expands puts of sets *)
          refl t'.

Ltac reflop_data o :=
  let t := eval simpl in (Go.step (DataOp o)) in
  refl t.

Ltac reflop_glob o :=
  let t := eval simpl in (Go.step (LockGlobalOp o)) in
  refl t.

Definition reify T (op : Op T)  : RTerm.t gs gs T.
  destruct op.
  - destruct o eqn:?;
    match goal with
    | [ H : o = ?A |- _ ] => let x := reflop_fs A in idtac x; exact x
    end.
    match goal with
    | [ H : o = ?A |- _ ] => let x := reflop_data A in idtac x; exact x
    end.
  - destruct o eqn:?;
    match goal with
    | [ H : o = ?A |- _ ] => let x := reflop_glob A in idtac x; exact x
    end.
Defined.

Definition dir : string.
Admitted.

Definition na : NonAtomicArgs ().
Admitted.

Check (fun p : LockStatus * (() * (() * (LockStatus * ()))) => RTerm.NAMatch na
(RTerm.AndThenFS
     ((λ p0 : LockStatus * (() * (() * (LockStatus * ()))),
         RTerm.NotImpl
           ((λ p1 : LockStatus * (() * (() * (LockStatus * ()))),
               FS.unwrap
                 match p1.1 with
                 | Locked => None
                 | ReadLocked n => Some (ReadLocked (S n))
                 | Unlocked => Some (ReadLocked 0)
                 end) p0)) p)
     (λ s' : LockStatus,
        (λ p0 : LockStatus * (() * (() * (LockStatus * ()))) * LockStatus,
           RTerm.Puts
             ((λ (p1 : LockStatus * (() * (() * (LockStatus * ()))) * LockStatus) 
                 (e : fs),
                 {|
                 FS.heap := e.(FS.heap);
                 FS.dirlocks := <[dir:=(p1.2, ())]> e.(FS.dirlocks);
                 FS.dirents := e.(FS.dirents);
                 FS.inodes := e.(FS.inodes);
                 FS.fds := e.(FS.fds) |}) p0)) (p, s')))
(fun n : () =>
   RTerm.AndThenFS
     ((λ p0 : LockStatus * (() * (() * (LockStatus * ()))) * (),
         RTerm.NotImpl
           ((λ _ : LockStatus * (() * (() * (LockStatus * ()))) * (),
               FS.lookup FS.dirents dir) p0)) (p, n))
     (λ ents : gmap.gmap string FS.Inode,
        (λ p0 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                gmap.gmap string FS.Inode,
           RTerm.AndThenFS
             ((λ p1 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                      gmap.gmap string FS.Inode,
                 RTerm.NotImpl
                   ((λ p2 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                            gmap.gmap string FS.Inode,
                       FS.unwrap
                         match p2.1.1.1 with
                         | ReadLocked 0 => Some Unlocked
                         | ReadLocked (S n) => Some (ReadLocked n)
                         | _ => None
                         end) p1)) p0)
             (λ s' : LockStatus,
                (λ p1 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                        gmap.gmap string FS.Inode * LockStatus,
                   RTerm.AndThenFS
                     ((λ p2 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                              gmap.gmap string FS.Inode * LockStatus,
                         RTerm.Puts
                           ((λ (p3 : LockStatus * (() * (() * (LockStatus * ()))) *
                                     () * gmap.gmap string FS.Inode * LockStatus) 
                               (e : fs),
                               {|
                               FS.heap := e.(FS.heap);
                               FS.dirlocks := <[dir:=(p3.2, ())]> e.(FS.dirlocks);
                               FS.dirents := e.(FS.dirents);
                               FS.inodes := e.(FS.inodes);
                               FS.fds := e.(FS.fds) |}) p2)) p1)
                     (λ y : (),
                        (λ p2 : LockStatus * (() * (() * (LockStatus * ()))) * () *
                                gmap.gmap string FS.Inode * LockStatus * (),
                           RTerm.AndThenFS
                             ((λ p3 : LockStatus * (() * (() * (LockStatus * ()))) *
                                      () * gmap.gmap string FS.Inode * LockStatus *
                                      (),
                                 RTerm.NotImpl
                                   ((λ p4 : LockStatus *
                                            (() * (() * (LockStatus * ()))) * () *
                                            gmap.gmap string FS.Inode * LockStatus *
                                            (),
                                       such_that
                                         (λ (_ : fs) (l : list string),
                                            l
                                            ≡ₚ map fst
                                                 (fin_maps.map_to_list p4.1.1.2)))
                                      p3)) p2)
                             (λ l : list string,
                                (λ p3 : LockStatus *
                                        (() * (() * (LockStatus * ()))) * () *
                                        gmap.gmap string FS.Inode * LockStatus * () *
                                        list string,
                                   RTerm.NotImpl
                                     ((λ p4 : LockStatus *
                                              (() * (() * (LockStatus * ()))) * () *
                                              gmap.gmap string FS.Inode *
                                              LockStatus * () * 
                                              list string, 
                                         FS.createSlice p4.2) p3)) 
                                  (p2, l))) (p1, y))) (p0, s'))) 
          ((p,n), ents)))).

Definition s : LockStatus.
Admitted.

Definition u := ().

Check RTerm.NotImpl
           (FS.na_match na
              (and_then
                 (FS.unwrap
                    match (s, (u, ((), ()))).1 with
                    | Locked => None
                    | ReadLocked n => Some (ReadLocked (S n))
                    | Unlocked => Some (ReadLocked 0)
                    end)
                 (λ s' : LockStatus,
                    puts
                      (λ e : fs,
                         {|
                         FS.heap := e.(FS.heap);
                         FS.dirlocks := <[dir:=(s', ())]> e.(FS.dirlocks);
                         FS.dirents := e.(FS.dirents);
                         FS.inodes := e.(FS.inodes);
                         FS.fds := e.(FS.fds) |})))
              (λ _ : (),
                 and_then (FS.lookup FS.dirents dir)
                   (λ ents : gmap.gmap string FS.Inode,
                      and_then
                        (FS.unwrap
                           match (s, (u, ((), ()))).1 with
                           | ReadLocked 0 => Some Unlocked
                           | ReadLocked (S n) => Some (ReadLocked n)
                           | _ => None
                           end)
                        (λ s' : LockStatus,
                           and_then
                             (puts
                                (λ e : fs,
                                   {|
                                   FS.heap := e.(FS.heap);
                                   FS.dirlocks := <[dir:=(s', ())]> e.(FS.dirlocks);
                                   FS.dirents := e.(FS.dirents);
                                   FS.inodes := e.(FS.inodes);
                                   FS.fds := e.(FS.fds) |}))
                             (λ _ : (),
                                and_then
                                  (such_that
                                     (λ (_ : fs) (l : list string),
                                        l ≡ₚ map fst (fin_maps.map_to_list ents)))
                                  (λ l : list string, FS.createSlice l)))))).

Ltac reflproc p :=
  let t := eval simpl in (greedy_exec Go.sem p) in
  let t' := eval cbv [greedy_exec greedy_exec_partial greedy_exec_pool exec_pool_hd exec_step] in t in
  refl t'.

Definition reify_proc T (p : proc T)  : RTerm.t es es {T: Type & T}.
  destruct p eqn:?;
  match goal with
  | [ H : p = ?A |- _ ] => let x := reflproc A in idtac x; exact x
  end.
Defined.
