(in-package :bot)

(defun make-parser-name (class-name-symbol)
  (let ((name (symbol-name class-name-symbol)))
    (intern (concatenate 'string "PARSE-" name))))

(defun make-hash-parser-name (class-name-symbol)
  (let ((name (symbol-name class-name-symbol)))
    (intern (concatenate 'string "PARSE-" name "-FROM-HASH"))))

(defun make-keyword (sym)
  (let ((name (symbol-name sym)))
    (intern name "KEYWORD")))

(defun camel-case (str)
  (let ((parts (cl-ppcre:split "-+" str)))
    (format nil "~{~a~}" (cons (car parts) 
                               (mapcar #'string-capitalize (cdr parts))))))

(defun snake-case (str)
  (cl-ppcre:regex-replace-all "-" str "_"))

(defun screaming-snake-case (str)
  (string-upcase (snake-case str)))

(defun has-custom-key (x) 
  (and (consp x) (cadr x)))

(defun make-keys (slots case-fn)
  (mapcar (lambda (slot) 
            (if (has-custom-key slot)
                (cadr slot)
                (funcall case-fn (string-downcase (symbol-name (get-slot slot)))))) slots))

(defun make-init-arg (slot-spec) 
  (make-keyword (get-slot slot-spec)))

(defun get-slot-defs (slot-specs)
  (loop for slot-spec in slot-specs
     collect (let ((slot (get-slot slot-spec))
                   (init-arg (make-init-arg slot-spec)))
               `(,slot :accessor ,slot :initarg ,init-arg))))

(defun make-standard-slot (init-arg key json-obj)
  `(,init-arg (gethash ,key ,json-obj)))

(defun get-slot-type (slot) (caddr slot))

(defun make-object-slot (init-arg key slot json-obj)
  (let ((hash-parser-name (make-hash-parser-name (get-slot-type slot))))
    `(,init-arg (,hash-parser-name (gethash ,key ,json-obj)))))

(defun has-object-constructor (slot) 
  (and (consp slot) (caddr slot)))

(defmacro define-json-constructor (class-name slots case-fn)
  (let* ((keys (make-keys slots case-fn))
         (init-args (mapcar #'make-init-arg slots))
         (hash-parser-name (make-hash-parser-name class-name)))
    (alexandria:with-gensyms (json-obj)
      (let ((constructor-params 
             (apply #'append 
                    (loop for key in keys
                       for init-arg in init-args 
                       for slot in slots
                       collect (if (has-object-constructor slot)
                                   (make-object-slot init-arg key slot json-obj)
                                   (make-standard-slot init-arg key json-obj))))))
        `(defun ,hash-parser-name (,json-obj)
           (handler-case 
               (cond 
                 ((null ,json-obj) (vector))
                 ((consp ,json-obj)
                  (coerce (mapcar #',hash-parser-name ,json-obj) 'vector))
                 (t (make-instance ',class-name ,@constructor-params)))))))))

(defmacro define-parser (class-name slots case-fn)
  (let* ((hash-parser-name (make-hash-parser-name class-name))
         (parser-name (make-parser-name class-name)))
    (alexandria:with-gensyms (json-obj)
      `(progn 
           (define-json-constructor ,class-name ,slots ,case-fn)
           (defun ,parser-name (json)
             (let ((,json-obj (yason:parse json)))
               (,hash-parser-name ,json-obj)))))))

(defun get-slot (slot-spec) 
  (if (consp slot-spec)
      (car slot-spec)
      slot-spec))

(defmacro define-data-class (name slots)
    (let ((slot-defs (get-slot-defs slots)))
      `(defclass ,name ()
         ,slot-defs)))

(defmacro define-poclo (name slots case-fn)
  `(progn 
     (define-data-class ,name ,slots)
     (define-parser ,name ,slots ,case-fn)))
