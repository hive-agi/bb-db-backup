#!/usr/bin/env bb

;; chroma-check.bb — Check and manage Chroma vector database
;;
;; Usage:
;;   bb scripts/chroma-check.bb          # Check environment status
;;   bb scripts/chroma-check.bb start    # Start Chroma container
;;   bb scripts/chroma-check.bb stop     # Stop Chroma container
;;   bb scripts/chroma-check.bb status   # JSON status (for scripting)
;;
;; Environment variables:
;;   COMPOSE_FILE     — docker-compose.yml path (default: ./docker-compose.yml)
;;   CHROMA_PORT      — Chroma API port (default: 8000)
;;
;; Exit codes:
;;   0 — All checks passed / operation successful
;;   1 — Missing dependencies
;;   2 — Operation failed

(require '[babashka.process :as p]
         '[clojure.string :as str]
         '[cheshire.core :as json])

(def ^:const RESET  "\u001B[0m")
(def ^:const GREEN  "\u001B[32m")
(def ^:const YELLOW "\u001B[33m")
(def ^:const RED    "\u001B[31m")
(def ^:const CYAN   "\u001B[36m")
(def ^:const BOLD   "\u001B[1m")

(def chroma-port (or (System/getenv "CHROMA_PORT") "8000"))

(def compose-file
  (or (System/getenv "COMPOSE_FILE")
      (str (System/getProperty "user.dir") "/docker-compose.yml")))

(defn colorize [color text] (str color text RESET))
(defn bold [text] (str BOLD text RESET))
(defn icon-ok [] (colorize GREEN "✓"))
(defn icon-fail [] (colorize RED "✗"))
(defn icon-warn [] (colorize YELLOW "⚠"))
(defn icon-info [] (colorize CYAN "ℹ"))

;;; Checks

(defn cmd-ok? [& cmd]
  (try
    (-> (p/process cmd {:out :string :err :string})
        deref :exit zero?)
    (catch Exception _ false)))

(defn docker-ok? [] (cmd-ok? "docker" "info"))
(defn compose-ok? []
  (or (cmd-ok? "docker" "compose" "version")
      (cmd-ok? "docker-compose" "--version")))

(defn chroma-healthy? []
  (cmd-ok? "curl" "-sf" (str "http://localhost:" chroma-port "/api/v2/heartbeat")))

(defn compose-file? [] (.exists (java.io.File. compose-file)))

(defn ollama-ok? [] (cmd-ok? "ollama" "--version"))

(defn ollama-model? [model]
  (try
    (let [r (-> (p/process ["ollama" "list"] {:out :string :err :string}) deref)]
      (and (zero? (:exit r)) (str/includes? (:out r) model)))
    (catch Exception _ false)))

;;; Compose operations

(defn compose-cmd []
  (if (cmd-ok? "docker" "compose" "version")
    ["docker" "compose"]
    ["docker-compose"]))

(defn start-chroma! []
  (println (str (icon-info) " Starting Chroma container..."))
  (let [cmd (concat (compose-cmd) ["-f" compose-file "up" "-d"])
        r   (-> (p/process cmd {:out :inherit :err :inherit}) deref)]
    (if-not (zero? (:exit r))
      (do (println (str (icon-fail) " Failed to start Chroma")) false)
      (do
        (println (str (icon-ok) " Container started, waiting for health..."))
        (Thread/sleep 3000)
        (loop [n 0]
          (cond
            (chroma-healthy?)
            (do (println (str (icon-ok) " Chroma is healthy")) true)
            (>= n 10)
            (do (println (str (icon-warn) " Not yet healthy, may need more time")) true)
            :else (do (Thread/sleep 2000) (recur (inc n)))))))))

(defn stop-chroma! []
  (println (str (icon-info) " Stopping Chroma container..."))
  (let [cmd (concat (compose-cmd) ["-f" compose-file "down"])
        r   (-> (p/process cmd {:out :inherit :err :inherit}) deref)]
    (if (zero? (:exit r))
      (println (str (icon-ok) " Stopped"))
      (println (str (icon-fail) " Failed to stop")))))

;;; Output

(defn json-status []
  (println (json/generate-string
            {:docker        (docker-ok?)
             :docker-compose (compose-ok?)
             :ollama        (ollama-ok?)
             :ollama-model  (ollama-model? "nomic-embed-text")
             :chroma        (chroma-healthy?)
             :compose-file  (compose-file?)})))

(defn check-line [label ok? & [note]]
  (println (str "  " (if ok? (icon-ok) (icon-fail)) " " label
                (when note (str " " (colorize CYAN note))))))

(defn print-checks []
  (println)
  (println (bold "=== Chroma Environment Check ==="))
  (println)
  (let [d?  (docker-ok?)
        dc? (compose-ok?)
        ol? (ollama-ok?)
        om? (ollama-model? "nomic-embed-text")
        cf? (compose-file?)
        ch? (chroma-healthy?)]
    (println (bold "Dependencies:"))
    (check-line "Docker daemon"     d?)
    (check-line "docker-compose"    dc?)
    (check-line "docker-compose.yml" cf?)
    (check-line "Ollama"            ol?)
    (check-line "nomic-embed-text"  om?
                (when (and ol? (not om?)) "(run: ollama pull nomic-embed-text)"))
    (println)
    (println (bold "Services:"))
    (check-line "Chroma vector DB"  ch?
                (when (and dc? cf? (not ch?)) "(run: bb chroma-check start)"))
    (println)
    (if (and d? dc? ol? om? ch?)
      (do (println (colorize GREEN "All systems operational.")) 0)
      (do (println (colorize YELLOW "Some checks failed. See above.")) 1))))

(defn usage []
  (println "Usage: bb scripts/chroma-check.bb [command]")
  (println)
  (println "Commands:")
  (println "  (none)   Check environment (human-readable)")
  (println "  start    Start Chroma container")
  (println "  stop     Stop Chroma container")
  (println "  status   JSON status output")
  (println "  help     Show this help"))

(let [cmd (first *command-line-args*)]
  (case cmd
    nil     (System/exit (print-checks))
    "start" (System/exit (if (start-chroma!) 0 2))
    "stop"  (do (stop-chroma!) (System/exit 0))
    "status" (do (json-status) (System/exit 0))
    "help"  (do (usage) (System/exit 0))
    (do (println (str "Unknown: " cmd)) (usage) (System/exit 1))))
