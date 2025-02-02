(*************************************************************************)
(*                                                                       *)
(*                              OCamlClean                               *)
(*                                                                       *)
(*                             Benoit Vaugon                             *)
(*                                                                       *)
(*    This file is distributed under the terms of the CeCILL license.    *)
(*    See file ../LICENSE-en.                                            *)
(*                                                                       *)
(*************************************************************************)

open Instr;;

type mark = Unused | Valid | Invalid

let compute_nexts code =
  let f i bc =
    match bc with
      | Branch ptr ->
        [ ptr.instr_ind ]
          
      | Branchif ptr | Branchifnot ptr | Beq (_, ptr) | Bneq (_, ptr)
      | Blint (_, ptr) | Bleint (_, ptr) | Bgtint (_, ptr) | Bgeint (_, ptr)
      | Bultint (_, ptr) | Bugeint (_, ptr) | Pushretaddr ptr | Pushtrap ptr ->
        [ succ i ; ptr.instr_ind ]

      | Switch (_, tab) ->
        Array.to_list (Array.map (fun ptr -> ptr.instr_ind) tab)

      | Grab _ ->
        [ pred i ; succ i ]

      | Return _ | Appterm (_, _) | Raise | Reraise | Raisenotrace | Stop ->
        []

      | Apply n when n > 3 ->
        []
          
      | _ ->
        [ succ i ]
  in
  Array.mapi f code
;;

let compute_marks code =
  let nexts = compute_nexts code in
  let nb_instr = Array.length code in
  let marks = Array.make nb_instr Unused in
  let passes = Array.make nb_instr Unused in
  let rec f i =
    match (marks.(i), passes.(i)) with
      | (Unused, Unused) ->
        marks.(i) <- Valid;
        passes.(i) <- Valid;
        List.iter f nexts.(i);
        passes.(i) <- Unused;
        
      | ((Unused | Valid), Valid) ->
        marks.(i) <- Invalid;
        passes.(i) <- Invalid;
        List.iter f nexts.(i);
        passes.(i) <- Valid;
        
      | _ ->
        ()
  in
  f 0;
  marks
;;

let replace_envaccs code data =
  let nb_instr = Array.length code in
  let marks = compute_marks code in
  let ptr_map = Array.make nb_instr (-1) in
  let new_globals = ref [] in
  let global_ind = ref (Array.length data) in
  let alloc_global ptr ptrs env_ind =
    let glob_ind = !global_ind in
    let ptrs_nb = Array.length ptrs in
    let update_env_assoc env_ofs fun_ptr =
      let env_assoc =
        try List.assoc fun_ptr.instr_ind !new_globals with Not_found ->
          let new_env_assoc = ref [] in
          new_globals := (fun_ptr.instr_ind, new_env_assoc) :: !new_globals;
          new_env_assoc
      in
      env_assoc :=
        (1 + env_ind + 3 * (ptrs_nb - env_ofs - 1), glob_ind) :: !env_assoc;
    in
    update_env_assoc (-1) ptr;
    Array.iteri update_env_assoc ptrs;
    incr global_ind;
    glob_ind
  in
  let setglobals_of_closure env_size ptr ptrs new_closure =
    let rec f i =
      if i > env_size then [ new_closure ] else
        let glob_ind = alloc_global ptr ptrs i in
        Acc 0 :: Setglobal glob_ind :: Pop 1 :: f (i + 1)
    in
    let glob_ind = alloc_global ptr ptrs 1 in
    Setglobal glob_ind :: f 2
  in
  let rec gen_new_code i j acc =
    if i = nb_instr then Array.of_list (List.rev acc) else (
      ptr_map.(i) <- j;
      match ((marks.(i) = Valid), code.(i)) with
        | (true, Closure (env_size, ptr)) when env_size > 0 ->
          let new_closure = Closure (0, ptr) in
          let instrs =  setglobals_of_closure env_size ptr [||] new_closure in
          gen_new_code (i + 1) (j + List.length instrs) (List.rev instrs @ acc)
        | (true, Closurerec (fun_nb, env_size, ptr, ptrs)) when env_size > 0 ->
          let new_closure = Closurerec (fun_nb, 0, ptr, ptrs) in
          let instrs = setglobals_of_closure env_size ptr ptrs new_closure in
          gen_new_code (i + 1) (j + List.length instrs) (List.rev instrs @ acc)
        | _ ->
          gen_new_code (i + 1) (j + 1) (code.(i) :: acc)
    )
  in
  let new_code = gen_new_code 0 0 [] in
  Step1.remap_code new_code ptr_map;
  let new_nexts = compute_nexts new_code in
  let remap_coverage = Array.make (Array.length new_code) false in
  let remap_envaccs (fun_ind, env_assoc) =
    let rec f i =
      if not remap_coverage.(i) then (
        remap_coverage.(i) <- true;
        begin match new_code.(i) with
          | Envacc n -> new_code.(i) <- Getglobal (List.assoc n !env_assoc)
          | _ -> ()
        end;
        List.iter f new_nexts.(i)
      );
    in
    f ptr_map.(fun_ind)
  in
  List.iter remap_envaccs !new_globals;
  let new_data = Array.make (Array.length data + !global_ind) (Obj.repr 0) in
  Array.blit data 0 new_data 0 (Array.length data);
  (new_code, new_data, new_nexts)
;;

let factor_globals code data nexts =
  let nb_instr = Array.length code in
  let marks = compute_marks code in
  let (accus, stacks, stack_sizes, _, _, _, _) = Step2.compute_deps code in
  let deps = Array.make nb_instr [] in
  let data_map = Array.init (Array.length data) (fun i -> i) in
  let ptr_map = Array.make nb_instr (-1) in
  let rec compute_orig instr_ind pos =
    if marks.(instr_ind) <> Valid then None else
      match (code.(instr_ind), accus.(instr_ind), stacks.(instr_ind)) with
        | (Push, [accu_dep], _) ->
          compute_orig accu_dep 0
        | (Acc n, _, stack_deps) -> (
          match stack_deps.(n) with
            | [ instr_ind' ] ->
              compute_orig instr_ind' (stack_sizes.(instr_ind) - n)
            | _ ->
              Some (instr_ind, pos)
        )
        | _ ->
          Some (instr_ind, pos)
  in
  let compute_deps instr_ind bc =
    if marks.(instr_ind) = Valid then
      match (bc, accus.(instr_ind)) with
        | (Setglobal glob_ind, [accu_dep]) when data.(glob_ind) = Obj.repr 0 ->
          begin match compute_orig accu_dep 0 with
            | Some (dep_ind, pos) ->
              deps.(dep_ind) <- (pos, glob_ind) :: deps.(dep_ind);
              code.(instr_ind) <- Const 0;
            | None ->
              ();
          end;
        | _ ->
          ();
  in
  Array.iteri compute_deps code;
  (***)
  let compute_assoc acc ((pos, glob_ind) as dep) =
    try
      let shared_glob_ind = List.assoc pos acc in
      data_map.(glob_ind) <- shared_glob_ind;
      acc
    with Not_found ->
      dep :: acc
  in
  let rec gen_new_code i j pra_ofs acc =
    if i = nb_instr then (pra_ofs, Array.of_list (List.rev acc)) else (
      ptr_map.(i) <- j;
      let assoc = List.fold_left compute_assoc [] deps.(i) in
      if assoc = [] then
        gen_new_code (i + 1) (j + 1) pra_ofs (code.(i) :: acc)
      else
        let assoc = List.sort compare assoc in
        let gen_rev_instrs acc (pos, glob_ind) =
          if pos = 0 then Setglobal glob_ind :: acc
          else
            let stack_ind =
              match nexts.(i) with
                | [] -> assert false
                | next_ind :: _ -> stack_sizes.(next_ind) - pos + 1
            in
            Setglobal glob_ind :: Acc stack_ind :: acc
        in
        let rev_instrs =
          Pop 1 :: Acc 0 ::
            List.fold_left gen_rev_instrs [ Push; code.(i) ] assoc
        in
        let instr_nb = List.length rev_instrs in
        let new_pra_ofs =
          match code.(i) with
            | Apply n when n >= 4 ->
              begin match stacks.(i).(n) with
                | [] -> pra_ofs
                | pushretaddr_ind :: _ ->
                  match code.(pushretaddr_ind) with
                    | Pushretaddr ptr -> (ptr, instr_nb - 1) :: pra_ofs
                    | _ -> assert false
              end;
            | _ -> pra_ofs
        in
        gen_new_code (i + 1) (j + instr_nb) new_pra_ofs (rev_instrs @ acc)
    )
  in
  let (pra_ofs, new_code) = gen_new_code 0 0 [] [] in
  Step1.remap_code new_code ptr_map;
  List.iter (fun (ptr, ofs) -> ptr.instr_ind <- ptr.instr_ind - ofs) pra_ofs;
  (***)
  let remap_getglobals instr_ind bc =
    match bc with
      | Getglobal n ->
        new_code.(instr_ind) <- Getglobal data_map.(n);
      | Getglobalfield (n, p) ->
        new_code.(instr_ind) <- Getglobalfield (data_map.(n), p);
      | _ ->
        ();
  in
  Array.iteri remap_getglobals new_code;
  (***)
  new_code
;;

let clean_environments code data =
  Printexc.record_backtrace true;
  let (code, data, nexts) = replace_envaccs code data in
  let code = factor_globals code data nexts in
  (code, data)
;;
