;; -*- Mode: LISP; Package: LEM -*-

(in-package :lem)

(defstruct leval-client
  hostname
  port
  socket)

(defvar *leval-default-hostname* "localhost")
(defvar *leval-default-port* 53912)

(defvar *leval-client*)
(defvar *leval-connected-p* nil)

(define-command leval () ()
  (uiop:run-program
   "xterm -e ros run -s leval-server -l \"leval-server/start.lisp\" &")
  (loop :for error-p := nil :do
    (sleep 1)
    (handler-case (leval-connect-internal *leval-default-hostname*
                                          *leval-default-port*)
      (error () (setq error-p t)))
    (when (not error-p)
      (return t))))

(defun leval-send (event)
  (let ((stream (usocket:socket-stream (leval-client-socket *leval-client*))))
    (print event stream)
    (force-output stream)
    (prog1 (ignore-errors (read stream nil))
      (leval-connect-internal (leval-client-hostname *leval-client*)
                              (leval-client-port *leval-client*)))))

(defun leval-send-rex (string package-name)
  (leval-send (list :eval string package-name)))

(defun leval-send-find-package (string)
  (leval-send (list :find-package string)))

(defun leval-send-macroexpand-1 (string package-name)
  (leval-send (list :macroexpand-1 string package-name)))

(defun leval-send-macroexpnad (string package-name)
  (leval-send (list :macroexpand string package-name)))

(defun leval-send-complete-symbol (string package-name)
  (let ((strings (leval-send (list :complete-symbol string package-name))))
    (cond ((null strings) nil)
          ((null (cdr strings)) (car strings))
          (t (values (car strings) (cdr strings))))))

(defun leval-send-describe-symbol (string package-name)
  (leval-send (list :describe-symbol string package-name)))

(defun leval-send-disassemble-symbol (string package-name)
  (leval-send (list :disassemble-symbol string package-name)))

(defun leval-send-arglist (string package-name)
  (leval-send (list :arglist string package-name)))

(defun leval-send-trace (string untrace-p package-name)
  (leval-send (list :trace string untrace-p package-name)))

(defun leval-update-package (package-name)
  (let ((prev-package-name
         (buffer-get (window-buffer)
                     :leval-prev-package)))
    (when (or (null prev-package-name)
              (not (equal package-name prev-package-name)))
      (when (leval-send-find-package package-name)
        (buffer-put (window-buffer)
                    :leval-current-package package-name)
        (buffer-put (window-buffer)
                    :leval-prev-package package-name)
        t))))

(defun leval-current-package (&optional (buffer (window-buffer)))
  (or (leval-send-find-package (lisp-buffer-package buffer))
      "COMMON-LISP-USER"))

(defvar *leval-mode-keymap*
  (make-keymap "leval"))

(define-major-mode leval-mode nil
  (:name "leval"
   :keymap *leval-mode-keymap*
   :syntax-table *lisp-syntax-table*)
  (buffer-put (window-buffer)
              :modeline-format
              (append *modeline-default-format*
                      (list
                       " "
                       (lambda (window)
                         (leval-current-package
                          (window-buffer window)))))))

(defun leval-connect-internal (hostname port)
  (cond ((typep port '(integer 1024 65535))
         (let ((socket (usocket:socket-connect hostname port)))
           (setq *leval-client*
                 (make-leval-client :hostname hostname
                                    :port port
                                    :socket socket))
           t))
        (t nil)))

(define-command leval-connect (hostname port)
  ((list (minibuf-read-string "Host: " *leval-default-hostname*)
         (parse-integer (minibuf-read-string
                         "Port: "
                         (write-to-string *leval-default-port*))
                        :junk-allowed t)))
  (cond ((leval-connect-internal hostname port)
         (unless *leval-connected-p*
           (leval-mode)
           (define-command lisp-mode ()
             (leval-mode))
           (setq *leval-connected-p* t))
         (scan-file-property-list)
         t)
        (t
         (minibuf-print (format nil "Illegal port: ~a" port))
         nil)))

(define-key *leval-mode-keymap* (kbd "C-i") 'lisp-indent-line)
(define-key *leval-mode-keymap* (kbd "C-j") 'lisp-newline-and-indent)
(define-key *leval-mode-keymap* (kbd "M-j") 'lisp-newline-and-indent)
(define-key *leval-mode-keymap* (kbd "M-C-q") 'lisp-indent-sexp)
(define-key *leval-mode-keymap* (kbd "M-C-q") 'lisp-comment-or-uncomment-region)

(define-key *leval-mode-keymap* (kbd "C-x p") 'leval-set-package)
(define-command leval-set-package () ()
  (lisp-read-change-package
   #'(lambda (package-name)
       (leval-send-find-package package-name))
   nil))

(defun leval-eval-string (string)
  (minibuf-print
   (format nil "~{~a~^,~}"
           (leval-send-rex string
                           (leval-current-package)))))

(define-command leval-eval-region (&optional begin end) ("r")
  (unless (or begin end)
    (setq begin (region-beginning))
    (setq end (region-end)))
  (leval-eval-string (region-string begin end))
  t)

(define-key *leval-mode-keymap* (kbd "M-C-x") 'leval-eval-defun)
(define-command leval-eval-defun () ()
  (lisp-move-and-eval-sexp #'top-of-defun #'leval-eval-string))

(define-key *leval-mode-keymap* (kbd "C-x u") 'leval-eval-last-sexp)
(define-command leval-eval-last-sexp () ()
  (lisp-move-and-eval-sexp #'backward-sexp #'leval-eval-string))

(define-key *leval-mode-keymap* (kbd "C-x l") 'leval-load-file)
(define-key *leval-mode-keymap* (kbd "C-x C-l") 'leval-load-file)
(define-command leval-load-file (filename) ("fLoad File: ")
  (when (and (cl-fad:file-exists-p filename)
             (not (cl-fad:directory-pathname-p filename)))
    (leval-eval-string
     (format nil "(load ~s)" filename))))

(define-key *leval-mode-keymap* (kbd "C-x m") 'leval-macroexpand)
(define-key *leval-mode-keymap* (kbd "C-x C-m") 'leval-macroexpand)
(define-command leval-macroexpand (&optional arg) ("P")
  (let ((begin (point))
        (end (save-excursion
              (when (forward-sexp 1 t)
                (point)))))
    (when (and begin end)
      (let* ((string (region-string begin end))
             (expr-string
              (if (null arg)
                  (leval-send-macroexpand-1 string (leval-current-package))
                  (leval-send-macroexpand string (leval-current-package))))
             (buffer (get-buffer-create "*macroexpand*")))
        (let ((*current-window* (pop-to-buffer buffer)))
          (erase-buffer)
          (leval-mode)
          (insert-string expr-string))
        t))))

(defun leval-read-symbol (prompt &optional default)
  (when default
    (setq prompt (format nil "~a(~a) " prompt default)))
  (let ((str (minibuf-read-line prompt
                                ""
                                #'(lambda (str)
                                    (leval-send-complete-symbol
                                     str
                                     (leval-current-package)))
                                nil)))
    (if (equal "" str)
        (or default nil)
        str)))

(flet ((f (prompt send-function buffer-name)
          (let* ((name
                  (leval-read-symbol prompt))
                 (text
                  (funcall send-function name (leval-current-package)))
                 (buffer
                  (get-buffer-create buffer-name)))
            (let ((*current-window* (pop-to-buffer buffer)))
              (erase-buffer)
              (leval-mode)
              (insert-string text))
            t)))
  (define-key *leval-mode-keymap* (kbd "C-x d") 'leval-describe-symbol)
  (define-command leval-describe-symbol () ()
    (f "Describe: " #'leval-send-describe-symbol "*describe*"))
  (define-key *leval-mode-keymap* (kbd "C-x M-d") 'leval-disassemble-symbol)
  (define-command leval-disassemble-symbol () ()
    (f "Disassemble: " #'leval-send-disassemble-symbol "*disassemble*")))

(define-key *leval-mode-keymap* (kbd "C-M-i") 'leval-complete-symbol)
(define-command leval-complete-symbol () ()
  (lisp-popup-completion-symbol #'(lambda (str)
                                    (leval-send-complete-symbol
                                     str (leval-current-package))))
  t)

(define-key *leval-mode-keymap* (kbd "Spc") 'leval-self-insert-then-arg-list)
(define-command leval-self-insert-then-arg-list (n) ("p")
  (prog1 (self-insert n)
    (lisp-echo-arglist
     #'(lambda (string)
         (leval-send-arglist string
                             (leval-current-package))))))

(define-key *leval-mode-keymap* (kbd "C-x t") 'leval-trace)
(define-command leval-trace (symbol-name)
  ((list (leval-read-symbol "trace: ")))
  (leval-send-trace symbol-name nil (leval-current-package))
  t)

(define-key *leval-mode-keymap* (kbd "C-x T") 'leval-untrace)
(define-command leval-untrace (symbol-name)
  ((list (leval-read-symbol "untrace: " nil)))
  (leval-send-trace symbol-name t (leval-current-package))
  t)
