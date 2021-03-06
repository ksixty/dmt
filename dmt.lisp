;;;; dmt.lisp

;(defpackage #:dmt
;  (:use #:cl #:cffi)

(in-package #:dmt)

(defconstant +page-size+ 4096)

;; C bindings

(defctype :pid-t :long)

(defcfun "kill" :int
  (pid-t :int) (signal :int))

;; Linux process data structures

(macrolet ((def-proc-struct (name args)
             `(defstruct (,name
                          (:constructor ,(intern (format nil "MAKE-~a" name))
                                        ,args))
                ,@args)))
          (def-proc-struct proc-stat
              (pid comm state ppid pgrp session tty-nr tpgid
               flags minflt cminflt majflt cmajflt utime
               stime cutime cstime priority nice num-threads
               itrealvalue starttime vsize rss rsslim startcode
               endcode startstack kstkesp kstkeip signal blocked
               sigignore sigcatch wchan nswap cnswap exit-signal processor
               rt-priority policy delayacct-blkio-ticks guest-time cguest-time
               start-data end-data start-brk arg-start arg-end env-start env-end
               exit-codeq))
          (def-proc-struct proc-stat-memory
            (size resident shared text data)))

;; The Process class

(defclass process ()
  ((pid :initarg :pid
        :accessor process-pid)
   (stat :initarg :stat
         :accessor process-stat)
   (stat-memory :initarg :stat-memory
                :accessor process-stat-memory)
   (cmdline :initarg :cmdline)))

(defmethod process-cmdline ((obj process))
  (str:trim (format nil "~{~A ~}" (slot-value obj 'cmdline))))

(defun make-process (pid)
  "Queries OS for process PID and initializes a process object"
  (make-instance 'process
                 :pid pid
                 :stat (proc-stat pid)
                 :stat-memory (proc-stat-memory pid)
                 :cmdline (proc-cmdline pid)))

(defun proc-pathname (pid &optional file)
  (format nil "/proc/~d/~(~a~)" pid (or file "")))

(defun proc-stat-memory (pid)
  (let* ((path (proc-pathname pid  'statm))
         (stat (uiop:read-file-forms path)))
    (destructuring-bind (size resident shared _ text _ data) stat
       (make-proc-stat-memory size resident shared text data))))

(defun proc-cmdline (pid)
  (let ((path (proc-pathname pid 'cmdline)))
    (str:split-omit-nulls " " (uiop:read-file-string path))))

(defun read-proc-stat (pid)
  (let* ((path (proc-pathname pid 'stat))
         (stat (uiop:read-file-string path)))
    (ppcre:register-groups-bind (pid name state rest) ("([0-9]+) \\((.*)\\) ([A-Z]) (.*)" stat)
      (alexandria:flatten
       (list (parse-integer pid) name state (mapcar #'parse-integer (str:split " " rest)))))))


(defun parse-proc-stat (proc-stat-list)
  (apply #'make-proc-stat proc-stat-list))

(defun proc-stat (pid)
  (parse-proc-stat (read-proc-stat pid)))

(defun read-pid-from-pathname (pathname)
  (parse-integer (caddr (pathname-directory pathname))
                 :junk-allowed t))

(defun get-pids ()
  (let ((proc-contents (uiop:subdirectories #P"/proc/")))
    (serapeum:filter-map #'read-pid-from-pathname proc-contents)))

(defmacro map-pids (&body body)
  `(mapcar (lambda (pid) ,@body) (get-pids)))

(defun list-processes (&key sort-by)
  (let ((processes (map-pids (make-process pid))))
    (case sort-by
          ('pid     (sort processes #'< :key #'process-pid))
          ('name    (sort processes #'string< :key (lambda (it) (proc-stat-comm (process-stat it)))))
          ('cmdline (sort processes #'string> :key #'process-cmdline))
          ('memory  (sort processes #'> :key (lambda (it) (proc-stat-memory-resident (process-stat-memory it)))))
          (t        processes))))

(defun b (pages)
  (* pages +page-size+))

(defun kb (pages)
  (/ (b pages) 1024))

(defun mb (pages)
  (/ (kb pages) 1024))

(defmethod print-object ((obj process) stream)
  (with-slots (pid stat stat-memory) obj
        (format stream "#<~8d ~16a ~10,1,,-FM>"
                pid
                (str:prune 16 (proc-stat-comm stat) :ellipsis "")
                (mb (proc-stat-memory-resident stat-memory)))))

(defmethod print-object ((obj proc-stat-memory) stream)
  (with-slots (size resident shared text) obj
        (format stream "#S(PROC-STAT-MEMORY :RESIDENT ~5,1fM :SHARED ~5,1fM)"
                (mb resident) (mb shared))))

(defmethod print-object ((obj proc-stat) stream)
  (with-slots (comm) obj
        (format stream "#S(PROC-STAT (~a))"
                comm)))

(defun find-processes (name)
  (let ((processes (list-processes)))
    (remove-if-not (lambda (process) (or (string= name (proc-stat-comm (process-stat process)))
                                         (string= name (process-cmdline process))))
                   processes)))

(defmethod kill-process ((obj process) &optional (signal 9))
  (with-slots (pid) obj
    (kill pid signal)))
