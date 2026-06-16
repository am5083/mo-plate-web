(** Per-key token-bucket rate limiter.

    Used to keep one client from monopolising the single upstream session.
    Cheap critical section guarded by a stdlib mutex — fine because [allow] does
    no IO and never yields. *)

type bucket = {
  mutable tokens : float;
  mutable last : float; (* last refill time, seconds (Unix.gettimeofday) *)
}

type t = {
  capacity : float; (* max tokens (burst size) *)
  refill_per_sec : float; (* tokens regained per second *)
  tbl : (string, bucket) Hashtbl.t;
  mutex : Mutex.t;
}

(** [create ~capacity ~window_sec] allows [capacity] requests per key in a burst,
    refilling to full over [window_sec] seconds. *)
let create ~capacity ~window_sec =
  {
    capacity = float_of_int capacity;
    refill_per_sec = float_of_int capacity /. window_sec;
    tbl = Hashtbl.create 256;
    mutex = Mutex.create ();
  }

(** [allow t key now] consumes a token for [key]. Returns [true] if one was
    available (request permitted), [false] otherwise. [now] is Unix epoch
    seconds. *)
let allow t key now =
  Mutex.lock t.mutex;
  Fun.protect
    ~finally:(fun () -> Mutex.unlock t.mutex)
    (fun () ->
      let b =
        match Hashtbl.find_opt t.tbl key with
        | Some b -> b
        | None ->
            let b = { tokens = t.capacity; last = now } in
            Hashtbl.replace t.tbl key b;
            b
      in
      let elapsed = Float.max 0. (now -. b.last) in
      b.tokens <- Float.min t.capacity (b.tokens +. (elapsed *. t.refill_per_sec));
      b.last <- now;
      if b.tokens >= 1. then begin
        b.tokens <- b.tokens -. 1.;
        true
      end
      else false)

(** Drop buckets untouched for a while, so the table can't grow without bound
    under churn of distinct keys. Call occasionally. *)
let gc t ~older_than now =
  Mutex.lock t.mutex;
  Fun.protect
    ~finally:(fun () -> Mutex.unlock t.mutex)
    (fun () ->
      let stale =
        Hashtbl.fold
          (fun k b acc -> if now -. b.last > older_than then k :: acc else acc)
          t.tbl []
      in
      List.iter (Hashtbl.remove t.tbl) stale)
