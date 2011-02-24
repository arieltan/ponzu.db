#|
  This file is a part of PonzuDB package.
  URL: http://github.com/fukamachi/ponzu.db
  Copyright (c) 2011 Eitarow Fukamachi <e.arrows@gmail.com>

  PonzuDB is freely distributable under the LLGPL License.
|#

#|
  Ponzu.Db.Table
  Functions for database tables.

  Author: Eitarow Fukamachi (e.arrows@gmail.com)
|#

(ponzu.db.util:namespace ponzu.db.table
  (:use :cl)
  (:import-from :clsql
                :enable-sql-reader-syntax
                :create-view-from-class
                :select
                :sql-expression
                :sql-operator
                :table-exists-p
                :sql-and
                :sql-=
                :sql-in)
  (:import-from :clsql-sys :standard-db-class)
  (:import-from :ponzu.db.record
                :<ponzu-db-record>
                :save))

(cl-annot:enable-annot-syntax)

@export
(defclass <ponzu-db-table> (clsql-sys::standard-db-class) ()
  (:documentation "Metaclass for database tables."))

@export
(defmethod create-instance ((table <ponzu-db-table>) &rest initargs)
  "Same as `make-instance' except for calling `save' it then.

Example:
  (create-instance 'person :name \"Eitarow Fukamachi\")"
  (let ((new-instance (apply #'make-instance table initargs)))
    (save new-instance)
    new-instance))

(defun remove-nil-from-plist (plist)
  (loop for (k v) on plist by #'cddr
        unless (eq v nil)
          append (list k v)))

@export
(defmethod fetch ((table symbol) ids-or-key
                  &key where conditions order offset limit group-by)
  (fetch (find-class table) ids-or-key
         where conditions order offset limit group-by))

@export
(defmethod fetch ((table <ponzu-db-table>) ids-or-key
                  &key where conditions order offset limit group-by)
  "Find records from `table' and return it.
`ids-or-key' must be :first, :all, or a number, represents primary key, or the list.

Example:
  ;; Fetch a record, id=1.
  (fetch person 1)
  ;; Fetch records, country=jp
  (fetch person :conditions '(:country \"jp\"))"
  (setf table (class-name table))
  (etypecase ids-or-key
    (keyword (ecase ids-or-key
               (:first
                (car
                 (apply #'select table :flatp t
                        (remove-nil-from-plist
                         `(:limit 1
                           :offset ,offset
                           :order ,order
                           :group-by ,group-by
                           :where ,(cond
                                     ((and where conditions)
                                      (sql-and where (normalize-conditions conditions)))
                                     (where where)
                                     (conditions (normalize-conditions conditions))))))))
               (:all (select table :flatp t))))
    (number
     (car
      (apply #'select table
             :where
             (cond
               ((and where conditions)
                (sql-and (sql-= (sql-expression :attribute "id") ids-or-key) where (normalize-conditions conditions)))
               (where (sql-and (sql-= (sql-expression :attribute "id") ids-or-key) where))
               (conditions (sql-and (sql-= (sql-expression :attribute "id") ids-or-key) (normalize-conditions conditions)))
               (t (sql-= (sql-expression :attribute "id") ids-or-key)))
             :flatp t
             (remove-nil-from-plist
              `(:order ,order :group-by ,group-by)))))
    (cons
     (apply #'select table
            :where
            (if where
                (sql-and (sql-in (sql-expression :attribute "id") ids-or-key) where)
                (sql-in (sql-expression :attribute "id") ids-or-key))
            :flatp t
            (remove-nil-from-plist
             `(:limit ,limit
               :offset ,offset
               :order ,order
               :group-by ,group-by))))))

@export
(defmacro deftable (class supers slots &optional cl-options)
  "Define a table schema. This is just a wrapper of `clsql:def-view-class',
so, see CLSQL documentation to get more informations.
<http://clsql.b9.com/manual/def-view-class.html>"
  `(prog1
     (clsql:def-view-class ,class (<ponzu-db-record> ,@supers)
      ,slots
      ,@(if (find :metaclass `,cl-options :key #'car)
            `,cl-options
            (cons '(:metaclass <ponzu-db-table>) `,cl-options)))
     (unless (table-exists-p ',class)
       (create-view-from-class ',class))
     (setf ,class (find-class ',class))))

(defun normalize-conditions (conditions)
  (apply #'sql-and
         (loop for (k v) on conditions by #'cddr
               collect (sql-= (sql-expression :attribute (symbol-name k)) v))))
