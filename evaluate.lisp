
(in-package :cl-conllu)

;; Functions for evaluating parsers


(defvar *deprel-value-list*
  '("nsubj"
    "obj"   "iobj"
    "csubj" "ccomp" "xcomp"
    "obl"   "vocative"
    "expl"  "dislocated"
    "advcl" "advmod"
    "discourse"
    "aux"  "cop"
    "mark" "nmod" "appos"
    "nummod"
    "acl"
    "amod"
    "det"
    "clf"
    "case"
    "conj"
    "cc"
    "fixed"
    "flat"
    "compound"
    "list"
    "parataxis"
    "orphan"
    "goeswith"
    "reparandum"
    "punct"
    "root"
    "dep")
  "List of the 37 universal syntactic relations in UD.")

(defvar *upostag-value-list*
  '("ADJ"
    "ADP"
    "ADV"
    "AUX"
    "CCONJ"
    "DET"
    "INTJ"
    "NOUN"
    "NUM"
    "PART"
    "PRON"
    "PROPN"
    "PUNCT"
    "SCONJ"
    "SYM"
    "VERB"
    "X")
  "List of universal part-of-speech categories in UD 2.0.")

(defun token-diff (tk1 tk2 &key (fields *token-fields*) (test #'equal) (simple-dep nil))
  (loop for field in fields
	for res = (if (and (equal field 'deprel) simple-dep)
		      (funcall test
			       (simple-deprel (slot-value tk1 field))
			       (simple-deprel (slot-value tk2 field)))
		      (funcall test
			       (slot-value tk1 field)
			       (slot-value tk2 field)))
	unless res
	collect (list field (slot-value tk1 field) (slot-value tk2 field))))


(defun sentence-diff (sent1 sent2 &key (fields *token-fields*)
				    (test #'equal) (simple-dep nil) (punct t))
  (assert (equal (sentence-size sent1) (sentence-size sent2)))
  (loop for tk1 in (remove-if (lambda (tk)
				(and (not punct) (equal "PUNCT" (token-upostag tk))))
			      (sentence-tokens sent1))
	for tk2 in (remove-if (lambda (tk)
				(and (not punct) (equal "PUNCT" (token-upostag tk))))
			      (sentence-tokens sent2))
	for diff = (token-diff tk1 tk2 :fields fields :test test :simple-dep simple-dep) 
	when diff
	collect (list (token-id tk1) diff)))


(defun attachment-score-by-sentence (list-sent1 list-sent2 &key (fields *token-fields*)
							     (punct t) (simple-dep nil))
  "Attachment score by sentence (macro-average).

   The attachment score is the percentage of words that have correct
   arcs to their heads. The unlabeled attachment score (UAS) considers
   only who is the head of the token, while the labeled attachment
   score (LAS) considers both the head and the arc label (dependency
   label / syntactic class).

   References:
     - Dependency Parsing. Kubler, Mcdonald and Nivre (pp.79-80)"
  (let ((ns (mapcar #'(lambda (x y)
			(- 1.0
			   (/ (length (sentence-diff x y :fields fields
						     :punct punct
						     :simple-dep simple-dep))
			      (sentence-size y))))
		    list-sent1 list-sent2)))
    (/ (apply #'+ ns) (float (length ns)))))


(defun attachment-score-by-word (list-sent1 list-sent2 &key (fields *token-fields*)
					    (punct t) (simple-dep nil))
  "Attachment score by word (micro-average). See also the
  `attachment-score-by-sentence`.

   References:
     - Dependency Parsing. Kubler, Mcdonald and Nivre (pp.79-80)"
  (let ((total-words (apply #'+ (mapcar #'sentence-size list-sent1)))
	(wrong-words (reduce #'+ (mapcar #'(lambda (x y)
					     (sentence-diff x y :fields fields
							    :punct punct
							    :simple-dep simple-dep))
					 list-sent1
					 list-sent2)
			     :key #'length
			     :initial-value 0)))
    (- 1.0 (/ wrong-words total-words))))


(defun recall (list-sent1 list-sent2 deprel &key (head-error nil) (label-error t) (simple-deprel nil))
  "Restricted to words which are originally of syntactical class
  (dependency type to head) `deprel`, returns the recall:
   the number of true positives divided by the number of words
   originally positive (that is, correctly of class `deprel`).

   head-error and label-error define what is considered an error (a
   false negative)"
  (labels ((token-deprel-chosen (tk)
	     (if simple-deprel
		 (token-simple-deprel tk)
		 (token-deprel tk))))
    (assert
     (or head-error
	 label-error)
     ()
     "Error: At least one error must be used!")
    (let ((total-words
	   (length
	    (remove-if-not
	     #'(lambda (x)
		 (equal x deprel))
	     (mappend #'sentence-tokens
		      list-sent2)
	     :key #'token-deprel-chosen)))
	  (wrong-words
	   (length
	    (remove-if-not
	     #'(lambda (x)
		 (equal x deprel))
	     (mappend
	      #'identity
	      (mapcar
	       #'(lambda (sent1 sent2)
		   (disagreeing-words
		    sent1 sent2
		    :head-error head-error
		    :label-error label-error))
	       list-sent1
	       list-sent2))
	     :key #'(lambda (disag-pair)
		      (token-deprel-chosen
		       (second disag-pair)))))))
      (if (eq total-words
	      0)
	  nil
	  (/ (float (- total-words wrong-words))
	     total-words)))))

(defun precision (list-sent1 list-sent2 deprel &key (head-error nil)
						 (label-error t) (simple-deprel nil))
  "Restricted to words which are classified as of syntactical class
   (dependency type to head) `deprel`, returns the precision:
   the number of true positives divided by the number of words
   predicted positive (that is, predicted as of class `deprel`).

   head-error and label-error define what is considered an error (a
   false positive)"
  (labels ((token-deprel-chosen (tk)
	     (if simple-deprel
		 (token-simple-deprel tk)
		 (token-deprel tk))))
    (assert
     (or head-error
	 label-error)
     ()
     "Error: At least one error must be used!")
    (let ((classified-words
	   (length
	    (remove-if-not
	     #'(lambda (x)
		 (equal x deprel))
	     (mappend #'sentence-tokens
		      list-sent1)
	     :key #'token-deprel-chosen)))
	  (wrong-words
	   (length
	    (remove-if-not
	     #'(lambda (x)
		 (equal x deprel))
	     (mappend
	      #'identity
	      (mapcar
	       #'(lambda (sent1 sent2)
		   (disagreeing-words
		    sent1 sent2
		    :head-error head-error
		    :label-error label-error))
	       list-sent1
	       list-sent2))
	     :key #'(lambda (disag-pair)
		      (token-deprel-chosen
		       (first disag-pair)))))))
      (if (eq classified-words
	      0)
	  nil
	  (/ (float (- classified-words wrong-words))
	     classified-words)))))

(defun projectivity-accuracy (list-sent1 list-sent2)
  (let ((N (length list-sent1))
	(correct 0))
    (mapcar
     #'(lambda (x y)
       (if (eq (non-projective? x)
	       (non-projective? y))
	   (incf correct)))
     list-sent1
     list-sent2)
    (if (eq N 0)
	nil
	(/ (float correct)
	   N))))

(defun projectivity-precision (list-sent1 list-sent2)
  (let ((number-of-positives
	 (length (remove-if-not
		  #'non-projective?
		  list-sent1)))
	(true-positives 0))
    (mapcar
     #'(lambda (x y)
	 (if (and
	      (eq (non-projective? x) t)
	      (eq (non-projective? y) t))
	     (incf true-positives)))
     list-sent1
     list-sent2)
    (if (eq 0
	    number-of-positives)
	nil
	(/ (float true-positives)
	   number-of-positives))))

(defun projectivity-recall (list-sent1 list-sent2)
  (let ((number-of-projectives
	 (length (remove-if-not
		  #'non-projective?
		  list-sent2)))
	(true-positives 0))
    (mapcar
     #'(lambda (x y)
	 (if (and
	      (eq (non-projective? x) t)
	      (eq (non-projective? y) t))
	     (incf true-positives)))
     list-sent1
     list-sent2)
    (if (eq 0
	    number-of-projectives)
	nil
	(/ (float true-positives)
	   number-of-projectives))))



(defun confusion-matrix (list-sent1 list-sent2 &key (normalize nil) (tag 'deprel))
  "Returns a hash table where keys are lists (deprel1 deprel2) and
   values are fraction of classifications as deprel1 of a word that
   originally was deprel2."
  (let* ((M (make-hash-table :test #'equal))
	 (all-words-pair-list
	  (mapcar
	   #'list
	   (mappend #'sentence-tokens list-sent1)
	   (mappend #'sentence-tokens list-sent2)))
	 (N (coerce (length all-words-pair-list) 'float))
	 (value-list (ecase tag
		       (deprel *deprel-value-list*)
		       (upostag *upostag-value-list*)))
	 (value-function (ecase tag
			   (deprel #'token-simple-deprel)
			   (upostag #'token-upostag))))
    (assert
     (every #'identity
	    (mapcar
	     #'(lambda (pair)
		 (let ((tk1 (first pair))
		       (tk2 (second pair)))
		   (and (equal (token-id tk1)
			       (token-id tk2))
			(equal (token-form tk1)
			       (token-form tk2)))))
	     all-words-pair-list))
     ()
     "Error: Sentence words do not match.")
    
    (dolist (rel1 value-list)
      (dolist (rel2 value-list)
	(setf (gethash `(,rel1 ,rel2) M) 0)))
    
    (dolist (pair all-words-pair-list)
      ;; (format t "~a ~%" (mapcar value-function
      ;; 		     pair))
      (incf (gethash
	     (mapcar value-function
		     pair)
	     M)))

    (if normalize
	(dolist (rel1 value-list M)
	  (dolist (rel2 value-list)
	    (if (not
		 (eq 0
		     (gethash `(,rel1 ,rel2) M)))
		(setf (gethash `(,rel1 ,rel2) M)
		      (/ (gethash `(,rel1 ,rel2) M)
			 N))))))
    M))

(defun format-matrix (matrix &key (stream *standard-output*))
  (let* ((M (alexandria:hash-table-alist matrix))
	(row-keys
	 (sort
	  (remove-duplicates
	   (mapcar
	    #'(lambda (x) (first (car x)))
	    M))
	  #'string<))
	(column-keys
	 (sort
	  (remove-duplicates
	   (mapcar
	    #'(lambda (x) (second (car x)))
	    M))
	  #'string<)))

    (format stream "~{~15a |~^ ~}~%" (cons " " column-keys))
    (dolist (dep1 row-keys)
      (let ((L (reverse (remove-if-not #'(lambda (x) (equal x dep1)) M
				       :key #'(lambda (x) (first (car x)))))))
	(format stream "~{~15a |~^ ~}~%"
		(cons dep1 (mapcar #'(lambda (x) (cdr x)) L)))))))

(defun simple-deprel (deprel)
  (car (ppcre:split ":" deprel)))

(defun token-simple-deprel (token)
  (simple-deprel (token-deprel token)))


(defun disagreeing-words (sent1 sent2 &key (head-error t) (label-error t) (upostag-error nil) (remove-punct nil) (simple-deprel nil))
  "Returns a list of disagreements in dependency parsing (either head
   or label):

   a list (w1,w2) where w1 is a word of sent1, w2 is its matching word
   on sent2 and they disagree.

   If head-error is true, getting the wrong head is considered a
   disagreement (an error).
   If label-error is true, getting the wrong label (type of dependency
   to head) is considered a disagreement (an error).
   By default both are errors.

   We assume that sent1 is the classified result and sent2 is the
   golden (correct) sentence."
  (labels ((token-deprel-chosen (tk)
			       (if simple-deprel
				   (token-simple-deprel tk)
				   (token-deprel tk))))
    (assert
     (every #'identity
	    (mapcar
	     #'(lambda (tk1 tk2)
		 (and (equal (token-id tk1)
			     (token-id tk2))
		      (equal (token-form tk1)
			     (token-form tk2))))
	     (sentence-tokens sent1)
	     (sentence-tokens sent2)))
     ()
     "Error: Sentence words do not match. The sentence pair ID is: ~a, ~a~%"
     (sentence-id sent1)
     (sentence-id sent2))
    (assert
     (or head-error
	 label-error
	 upostag-error)
     ()
     "Error: At least one error must be used!")
    (remove-if
     (lambda (x)
       (or
	(and remove-punct
	     (equal (token-upostag (first x))
		    "PUNCT"))
	(and      
	 (or (not head-error)
	     (equal (token-head (first x))
		    (token-head (second x))))
	 (or (not label-error)
	     (equal (token-deprel-chosen (first x))
		    (token-deprel-chosen (second x))))
	 (or (not upostag-error)
	     (equal (token-upostag (first x))
		    (token-upostag (second x)))))))
     (mapcar
      #'list
      (sentence-tokens sent1)
      (sentence-tokens sent2)))))

(defun beautify-disagreeing-words (disagreeing-list sentence &key (stream *standard-output*) (skip-correct t))
  "Prints to STREAM sentence text along with indication of disagreeing
   tokens.
   If SKIP-CORRECT, then sentence text of correct pairs is skipped."
  (if (or (null skip-correct)
	  disagreeing-list)
      (format
       stream
       "~a~%~{~a~%~}~%"
       (sentence->text sentence :ignore-mtokens t)
       disagreeing-list)))

