#!/usr/bin/env bb

;; bb nREPL client — evaluate Clojure code on a running nREPL server
;;
;; Uses bencode protocol for raw nREPL communication.
;; No cold start — talks to an already-running JVM.
;;
;; Usage:
;;   bb src/bb_backup/nrepl_client.bb --port 7888 --code '(+ 1 2)'
;;   echo '(System/getProperty "java.version")' | bb src/bb_backup/nrepl_client.bb --port 7888
;;   NREPL_PORT=7888 bb src/bb_backup/nrepl_client.bb --code '(+ 1 2)'
;;
;; Exit codes:
;;   0 — success (prints result value)
;;   1 — nREPL error (prints error to stderr)
;;   2 — connection failed

(require '[bencode.core :as b])
(import '[java.net Socket ConnectException]
        '[java.io PushbackInputStream])

(defn bytes->str [x]
  (if (bytes? x) (String. ^bytes x) (str x)))

(defn has-done? [status]
  (and (sequential? status)
       (some #(= "done" (bytes->str %)) status)))

(defn nrepl-eval
  "Evaluate code on nREPL at host:port. Returns {:value v :error e :out o}."
  [{:keys [host port code timeout-ms]
    :or {host "localhost" timeout-ms 120000}}]
  (let [sock (doto (Socket. ^String host ^int port)
               (.setSoTimeout (int timeout-ms)))
        in   (PushbackInputStream. (.getInputStream sock))
        out  (.getOutputStream sock)]
    (try
      (b/write-bencode out {"op" "eval" "code" code})
      (loop [result nil output (StringBuilder.) error (StringBuilder.)]
        (let [msg (try (b/read-bencode in) (catch Exception _ nil))]
          (if (nil? msg)
            {:value (some-> result bytes->str)
             :out   (let [s (str output)] (when (seq s) s))
             :error (let [s (str error)] (when (seq s) s))}
            (let [v      (get msg "value")
                  e      (get msg "err")
                  o      (get msg "out")
                  status (get msg "status")]
              (when o (.append output (bytes->str o)))
              (when e (.append error (bytes->str e)))
              (if (has-done? status)
                {:value (some-> (or v result) bytes->str)
                 :out   (let [s (str output)] (when (seq s) s))
                 :error (let [s (str error)] (when (seq s) s))}
                (recur (or v result) output error))))))
      (finally
        (.close sock)))))

(defn parse-args [args]
  (loop [args args
         opts {}]
    (if (empty? args)
      opts
      (case (first args)
        "--port" (recur (drop 2 args) (assoc opts :port (Integer/parseInt (second args))))
        "--host" (recur (drop 2 args) (assoc opts :host (second args)))
        "--code" (recur (drop 2 args) (assoc opts :code (second args)))
        "--timeout" (recur (drop 2 args) (assoc opts :timeout-ms (Integer/parseInt (second args))))
        ;; Positional: treat as code
        (recur (rest args) (assoc opts :code (first args)))))))

(defn -main [& args]
  (let [opts (parse-args args)
        port (or (:port opts)
                 (some-> (System/getenv "NREPL_PORT") Integer/parseInt)
                 7888)
        host (or (:host opts) "localhost")
        code (or (:code opts)
                 ;; Read from stdin if no --code provided
                 (let [in (slurp *in*)]
                   (when (seq (clojure.string/trim in)) in)))]
    (when-not code
      (binding [*out* *err*]
        (println "Error: No code provided. Use --code or pipe via stdin."))
      (System/exit 2))
    (try
      (let [{:keys [value error out]} (nrepl-eval {:host host :port port :code code})]
        (when out (print out))
        (when error
          (binding [*out* *err*] (print error))
          (when-not value (System/exit 1)))
        (when value (println value)))
      (catch ConnectException _
        (binding [*out* *err*]
          (println (str "Error: Cannot connect to nREPL at " host ":" port)))
        (System/exit 2)))))

(apply -main *command-line-args*)
