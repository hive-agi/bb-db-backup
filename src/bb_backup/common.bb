#!/usr/bin/env bb

;; Shared utilities for backup scripts
;; Used by bb-based backup tasks for common operations

(ns bb-backup.common
  (:require [babashka.fs :as fs]))

(defn recent-backup?
  "Check if a recent backup exists (less than min-age-hours old).
   Returns the path of the latest backup if it's too recent, nil otherwise."
  [backup-dir pattern min-age-hours]
  (let [files (->> (fs/glob backup-dir pattern)
                   (sort-by fs/last-modified-time)
                   reverse)]
    (when-let [latest (first files)]
      (let [age-ms   (- (System/currentTimeMillis)
                        (.toMillis (fs/last-modified-time latest)))
            min-ms   (* min-age-hours 3600 1000)]
        (when (< age-ms min-ms)
          (str latest))))))

(defn prune-old-backups!
  "Delete backup files older than retention-days."
  [backup-dir pattern retention-days]
  (let [cutoff-ms (* retention-days 24 3600 1000)
        now       (System/currentTimeMillis)]
    (doseq [f (fs/glob backup-dir pattern)
            :let [age-ms (- now (.toMillis (fs/last-modified-time f)))]
            :when (> age-ms cutoff-ms)]
      (println (str "  Pruning: " (fs/file-name f)))
      (fs/delete f))))

(defn ensure-dir! [dir]
  (fs/create-dirs dir))
