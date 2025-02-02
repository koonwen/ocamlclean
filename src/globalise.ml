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

let globalise code old_data_nb map =
  let glob_counter = ref old_data_nb in
  fun (setg_ind, nb_fields) ->
    match (code.(setg_ind - 1), code.(setg_ind)) with
    | Instr.Pop popn, Instr.Setglobal glob_ind ->
        map.(glob_ind) <- Some !glob_counter;
        for i = 0 to nb_fields - 1 do
          let acc_ind = setg_ind - 3 - (2 * i) in
          match code.(acc_ind) with
          | Instr.Acc old_ofs ->
              code.(acc_ind) <- Instr.Acc (old_ofs + i - nb_fields + 1);
              code.(acc_ind + 1) <- Instr.Setglobal !glob_counter;
              incr glob_counter
          | _ -> assert false
        done;
        code.(setg_ind - 1) <- Instr.Pop (popn - nb_fields)
    | _ -> assert false

let remap_globals map code =
  for i = 0 to Array.length code - 1 do
    match code.(i) with
    | Instr.Getglobalfield (g_ind, f_ind) -> (
        match map.(g_ind) with
        | Some new_ind -> code.(i) <- Instr.Getglobal (new_ind + f_ind)
        | None -> ())
    | _ -> ()
  done

let globalise_closures old_code old_data =
  let cleanables = Step1.compute_cleanables old_code old_data in
  let new_code, cleans = Step1.prepare_code old_code cleanables false in
  let old_data_nb = Array.length old_data in
  let code_info = List.map (fun (i, l) -> (i, List.length l)) cleans in
  let new_data_nb =
    List.fold_left (fun a (_, l) -> a + l) old_data_nb code_info
  in
  let new_data = Array.make new_data_nb (Obj.repr 0) in
  let map = Array.make old_data_nb None in
  Array.blit old_data 0 new_data 0 old_data_nb;
  List.iter (globalise new_code old_data_nb map) code_info;
  remap_globals map new_code;
  let new_code = Rmnop.clean new_code in
  (new_code, Data.clean new_code new_data)

let doit old_code old_data =
  let cleanables = Step1.compute_cleanables old_code old_data in
  let new_code, cleans = Step1.prepare_code old_code cleanables false in
  let old_data_nb = Array.length old_data in
  let code_info = List.map (fun (i, l) -> (i, List.length l)) cleans in
  let new_data_nb =
    List.fold_left (fun a (_, l) -> a + l) old_data_nb code_info
  in
  let new_data = Array.make new_data_nb (Obj.repr 0) in
  let map = Array.make old_data_nb None in
  Array.blit old_data 0 new_data 0 old_data_nb;
  List.iter (globalise new_code old_data_nb map) code_info;
  remap_globals map new_code;
  let new_code = Rmnop.clean new_code in
  (new_code, Data.clean new_code new_data)
