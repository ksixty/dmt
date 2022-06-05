;;;; dmt.asd

(asdf:defsystem #:dmt
  :description "Describe dmt here"
  :author "Your Name <your.name@example.com>"
  :license  "Specify license here"
  :version "0.0.1"
  :serial t
  :depends-on (#:cffi #:str #:serapeum #:cl-ppcre)
  :components ((:file "package")
               (:file "dmt")))
