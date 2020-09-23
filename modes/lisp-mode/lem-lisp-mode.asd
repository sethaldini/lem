(defsystem "lem-lisp-mode"
  :depends-on ("alexandria"
               "trivial-types"
               "usocket"
               "swank"
               "trivia"
               "uiop"
               "lem-core"
               "lem-process")
  :serial t
  :components ((:file "util")
               (:file "errors")
               (:file "swank-protocol")
               (:file "package")
               (:file "lisp-ui-mode")
               (:file "grammer")
               (:file "lisp-mode")
               (:file "repl")
               (:file "sldb")
               (:file "inspector")
               (:file "apropos-mode")
               (:file "paren-coloring")
               (:file "misc-commands")
               (:file "package-inferred-system")))
