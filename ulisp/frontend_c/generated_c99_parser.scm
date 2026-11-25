;;; =======================================================================
;;; Auto-generated Direct-Style Static Scheme PEG Parser (Issue #948)
;;; Grammar: C99 | Prefix: c99ds- | Entry: translation_unit
;;; Zero CPS combinators, zero closure chains, zero local set!.
;;; =======================================================================

;;; Hoisted Character Class Predicates
(define *c99ds-cc-0* (make-char-class-pred "a-zA-Z_" #f))
(define *c99ds-cc-1* (make-char-class-pred "a-zA-Z0-9_" #f))
(define *c99ds-cc-2* (make-char-class-pred "0-9a-fA-F" #f))
(define *c99ds-cc-3* (make-char-class-pred "0-9" #f))
(define *c99ds-cc-4* (make-char-class-pred "0-7" #f))
(define *c99ds-cc-5* (make-char-class-pred "1-9" #f))
(define *c99ds-cc-6* (make-char-class-pred "'\\\\\\r\\n" #t))
(define *c99ds-cc-7* (make-char-class-pred "\"\\\\\\r\\n" #t))
(define *c99ds-cc-8* (make-char-class-pred " \\t\\r\\n" #f))
(define *c99ds-cc-9* (make-char-class-pred "\\r\\n" #t))

;;; Rule: translation_unit [memo]
(define (c99ds-translation_unit ctx env pos)
  (peg-ds:rule-memo ctx 'translation_unit pos
    (lambda ()
      (let ((rdec_10 (let ((sp_0 (c99ds-ws ctx env pos)))
      (if sp_0
          (let ((sv_1 (parse-ctx-res-val ctx)))
            (let ((sp_2 (let ((rp1_8 (c99ds-external_declaration ctx env sp_0)))
                      (if rp1_8
                          (let ((rv1_9 (parse-ctx-res-val ctx)))
                            (if (<= rp1_8 sp_0)
                                (begin (parse-ctx-res-val-set! ctx (list rv1_9)) rp1_8)
                                (let rloop_4 ((rcur_5 rp1_8) (racc_6 (list rv1_9)))
                                  (let ((rnext_7 (c99ds-external_declaration ctx env rcur_5)))
                                    (if (and rnext_7 (> rnext_7 rcur_5))
                                        (rloop_4 rnext_7 (cons (parse-ctx-res-val ctx) racc_6))
                                        (begin (parse-ctx-res-val-set! ctx (reverse racc_6)) rcur_5))))))
                          #f))))
                (if sp_2
                    (let ((sv_3 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1 sv_3))
                          sp_2))
                    #f)))
          #f))))
      (if rdec_10
          (c99ds-decorate-rule 'translation_unit ctx env pos rdec_10 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: external_declaration [memo]
(define (c99ds-external_declaration ctx env pos)
  (peg-ds:rule-memo ctx 'external_declaration pos
    (lambda ()
      (or
      (c99ds-top_asm_decl ctx env pos)
      (c99ds-function_definition ctx env pos)
      (c99ds-declaration ctx env pos)))))

;;; Rule: top_asm_decl [memo]
(define (c99ds-top_asm_decl ctx env pos)
  (peg-ds:rule-memo ctx 'top_asm_decl pos
    (lambda ()
      (let ((rdec_32 (let ((sp_11 (or
            (peg-ds:lit ctx pos "__asm__" 7 #\_ "'__asm__'")
            (peg-ds:lit ctx pos "__asm" 5 #\_ "'__asm'")
            (peg-ds:lit ctx pos "asm" 3 #\a "'asm'"))))
      (if sp_11
          (let ((sv_12 (parse-ctx-res-val ctx)))
            (let ((sp_13 (let ((pred_15 (c99ds-ident_cont ctx env sp_11)))
                      (if pred_15
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_11)))))
                (if sp_13
                    (let ((sv_14 (parse-ctx-res-val ctx)))
                      (let ((sp_16 (c99ds-ws ctx env sp_13)))
                          (if sp_16
                              (let ((sv_17 (parse-ctx-res-val ctx)))
                                (let ((sp_18 (peg-ds:lit1 ctx sp_16 #\( "(" "'('")))
                                    (if sp_18
                                        (let ((sv_19 (parse-ctx-res-val ctx)))
                                          (let ((sp_20 (c99ds-ws ctx env sp_18)))
                                              (if sp_20
                                                  (let ((sv_21 (parse-ctx-res-val ctx)))
                                                    (let ((sp_22 (c99ds-asm_template ctx env sp_20)))
                                                        (if sp_22
                                                            (let ((sv_23 (parse-ctx-res-val ctx)))
                                                              (let ((sp_24 (peg-ds:lit1 ctx sp_22 #\) ")" "')'")))
                                                                  (if sp_24
                                                                      (let ((sv_25 (parse-ctx-res-val ctx)))
                                                                        (let ((sp_26 (c99ds-ws ctx env sp_24)))
                                                                            (if sp_26
                                                                                (let ((sv_27 (parse-ctx-res-val ctx)))
                                                                                  (let ((sp_28 (peg-ds:lit1 ctx sp_26 #\; ";" "';'")))
                                                                                      (if sp_28
                                                                                          (let ((sv_29 (parse-ctx-res-val ctx)))
                                                                                            (let ((sp_30 (c99ds-ws ctx env sp_28)))
                                                                                                (if sp_30
                                                                                                    (let ((sv_31 (parse-ctx-res-val ctx)))
                                                                                                      (begin
                                                                                                          (parse-ctx-res-val-set! ctx (list sv_12 sv_14 sv_17 sv_19 sv_21 sv_23 sv_25 sv_27 sv_29 sv_31))
                                                                                                          sp_30))
                                                                                                    #f)))
                                                                                          #f)))
                                                                                #f)))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_32
          (c99ds-decorate-rule 'top_asm_decl ctx env pos rdec_32 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: function_definition [bare]
(define (c99ds-function_definition ctx env pos)
  (c99ds-override-function-definition ctx env pos))

;;; Rule: declaration_list [memo]
(define (c99ds-declaration_list ctx env pos)
  (peg-ds:rule-memo ctx 'declaration_list pos
    (lambda ()
      (let ((rp1_37 (c99ds-declaration ctx env pos)))
      (if rp1_37
          (let ((rv1_38 (parse-ctx-res-val ctx)))
            (if (<= rp1_37 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_38)) rp1_37)
                (let rloop_33 ((rcur_34 rp1_37) (racc_35 (list rv1_38)))
                  (let ((rnext_36 (c99ds-declaration ctx env rcur_34)))
                    (if (and rnext_36 (> rnext_36 rcur_34))
                        (rloop_33 rnext_36 (cons (parse-ctx-res-val ctx) racc_35))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_35)) rcur_34))))))
          #f)))))

;;; Rule: declaration [memo]
(define (c99ds-declaration ctx env pos)
  (peg-ds:rule-memo ctx 'declaration pos
    (lambda ()
      (or
      (c99ds-explicit_declaration ctx env pos)
      (c99ds-typedef_declaration ctx env pos)))))

;;; Rule: explicit_declaration [memo]
(define (c99ds-explicit_declaration ctx env pos)
  (peg-ds:rule-memo ctx 'explicit_declaration pos
    (lambda ()
      (let ((rdec_48 (let ((sp_39 (c99ds-explicit_declaration_specifiers ctx env pos)))
      (if sp_39
          (let ((sv_40 (parse-ctx-res-val ctx)))
            (let ((sp_41 (let ((opt_43 (c99ds-init_declarator_list ctx env sp_39)))
                      (if opt_43
                          opt_43
                          (begin (parse-ctx-res-val-set! ctx #f) sp_39)))))
                (if sp_41
                    (let ((sv_42 (parse-ctx-res-val ctx)))
                      (let ((sp_44 (peg-ds:lit1 ctx sp_41 #\; ";" "';'")))
                          (if sp_44
                              (let ((sv_45 (parse-ctx-res-val ctx)))
                                (let ((sp_46 (c99ds-ws ctx env sp_44)))
                                    (if sp_46
                                        (let ((sv_47 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_40 sv_42 sv_45 sv_47))
                                              sp_46))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_48
          (c99ds-decorate-rule 'explicit_declaration ctx env pos rdec_48 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: typedef_declaration [memo]
(define (c99ds-typedef_declaration ctx env pos)
  (peg-ds:rule-memo ctx 'typedef_declaration pos
    (lambda ()
      (let ((rdec_57 (let ((sp_49 (c99ds-typedef_declaration_specifiers ctx env pos)))
      (if sp_49
          (let ((sv_50 (parse-ctx-res-val ctx)))
            (let ((sp_51 (c99ds-typedef_init_declarator_list ctx env sp_49)))
                (if sp_51
                    (let ((sv_52 (parse-ctx-res-val ctx)))
                      (let ((sp_53 (peg-ds:lit1 ctx sp_51 #\; ";" "';'")))
                          (if sp_53
                              (let ((sv_54 (parse-ctx-res-val ctx)))
                                (let ((sp_55 (c99ds-ws ctx env sp_53)))
                                    (if sp_55
                                        (let ((sv_56 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_50 sv_52 sv_54 sv_56))
                                              sp_55))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_57
          (c99ds-decorate-rule 'typedef_declaration ctx env pos rdec_57 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: declaration_specifiers [memo]
(define (c99ds-declaration_specifiers ctx env pos)
  (peg-ds:rule-memo ctx 'declaration_specifiers pos
    (lambda ()
      (or
      (c99ds-explicit_declaration_specifiers ctx env pos)
      (c99ds-typedef_declaration_specifiers ctx env pos)))))

;;; Rule: explicit_declaration_specifiers [memo]
(define (c99ds-explicit_declaration_specifiers ctx env pos)
  (peg-ds:rule-memo ctx 'explicit_declaration_specifiers pos
    (lambda ()
      (let ((rdec_96 (let ((sp_58 (let rloop_60 ((rcur_61 pos) (racc_62 '()))
            (let ((rnext_63 (let ((sp_64 (c99ds-decl_prefix ctx env rcur_61)))
                  (if sp_64
                      (let ((sv_65 (parse-ctx-res-val ctx)))
                        (let ((sp_66 (c99ds-ws ctx env sp_64)))
                            (if sp_66
                                (let ((sv_67 (parse-ctx-res-val ctx)))
                                  (begin
                                      (parse-ctx-res-val-set! ctx (list sv_65 sv_67))
                                      sp_66))
                                #f)))
                      #f))))
              (if (and rnext_63 (> rnext_63 rcur_61))
                  (rloop_60 rnext_63 (cons (parse-ctx-res-val ctx) racc_62))
                  (begin (parse-ctx-res-val-set! ctx (reverse racc_62)) rcur_61))))))
      (if sp_58
          (let ((sv_59 (parse-ctx-res-val ctx)))
            (let ((sp_68 (or
                      (let ((sp_70 (c99ds-builtin_type_specifier ctx env sp_58)))
                          (if sp_70
                              (let ((sv_71 (parse-ctx-res-val ctx)))
                                (let ((sp_72 (let rloop_74 ((rcur_75 sp_70) (racc_76 '()))
                                          (let ((rnext_77 (let ((sp_78 (c99ds-ws ctx env rcur_75)))
                                                (if sp_78
                                                    (let ((sv_79 (parse-ctx-res-val ctx)))
                                                      (let ((sp_80 (or
                                                                (c99ds-decl_prefix ctx env sp_78)
                                                                (c99ds-builtin_type_specifier ctx env sp_78))))
                                                          (if sp_80
                                                              (let ((sv_81 (parse-ctx-res-val ctx)))
                                                                (begin
                                                                    (parse-ctx-res-val-set! ctx (list sv_79 sv_81))
                                                                    sp_80))
                                                              #f)))
                                                    #f))))
                                            (if (and rnext_77 (> rnext_77 rcur_75))
                                                (rloop_74 rnext_77 (cons (parse-ctx-res-val ctx) racc_76))
                                                (begin (parse-ctx-res-val-set! ctx (reverse racc_76)) rcur_75))))))
                                    (if sp_72
                                        (let ((sv_73 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_71 sv_73))
                                              sp_72))
                                        #f)))
                              #f))
                      (let ((sp_82 (or
                                (c99ds-aggregate_or_enum_specifier ctx env sp_58)
                                (c99ds-typeof_specifier ctx env sp_58))))
                          (if sp_82
                              (let ((sv_83 (parse-ctx-res-val ctx)))
                                (let ((sp_84 (let rloop_86 ((rcur_87 sp_82) (racc_88 '()))
                                          (let ((rnext_89 (let ((sp_90 (c99ds-ws ctx env rcur_87)))
                                                (if sp_90
                                                    (let ((sv_91 (parse-ctx-res-val ctx)))
                                                      (let ((sp_92 (c99ds-decl_prefix ctx env sp_90)))
                                                          (if sp_92
                                                              (let ((sv_93 (parse-ctx-res-val ctx)))
                                                                (begin
                                                                    (parse-ctx-res-val-set! ctx (list sv_91 sv_93))
                                                                    sp_92))
                                                              #f)))
                                                    #f))))
                                            (if (and rnext_89 (> rnext_89 rcur_87))
                                                (rloop_86 rnext_89 (cons (parse-ctx-res-val ctx) racc_88))
                                                (begin (parse-ctx-res-val-set! ctx (reverse racc_88)) rcur_87))))))
                                    (if sp_84
                                        (let ((sv_85 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_83 sv_85))
                                              sp_84))
                                        #f)))
                              #f)))))
                (if sp_68
                    (let ((sv_69 (parse-ctx-res-val ctx)))
                      (let ((sp_94 (c99ds-ws ctx env sp_68)))
                          (if sp_94
                              (let ((sv_95 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_59 sv_69 sv_95))
                                    sp_94))
                              #f)))
                    #f)))
          #f))))
      (if rdec_96
          (c99ds-decorate-rule 'explicit_declaration_specifiers ctx env pos rdec_96 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: typedef_declaration_specifiers [memo]
(define (c99ds-typedef_declaration_specifiers ctx env pos)
  (peg-ds:rule-memo ctx 'typedef_declaration_specifiers pos
    (lambda ()
      (let ((rdec_121 (let ((sp_97 (let rloop_99 ((rcur_100 pos) (racc_101 '()))
            (let ((rnext_102 (let ((sp_103 (c99ds-decl_prefix ctx env rcur_100)))
                  (if sp_103
                      (let ((sv_104 (parse-ctx-res-val ctx)))
                        (let ((sp_105 (c99ds-ws ctx env sp_103)))
                            (if sp_105
                                (let ((sv_106 (parse-ctx-res-val ctx)))
                                  (begin
                                      (parse-ctx-res-val-set! ctx (list sv_104 sv_106))
                                      sp_105))
                                #f)))
                      #f))))
              (if (and rnext_102 (> rnext_102 rcur_100))
                  (rloop_99 rnext_102 (cons (parse-ctx-res-val ctx) racc_101))
                  (begin (parse-ctx-res-val-set! ctx (reverse racc_101)) rcur_100))))))
      (if sp_97
          (let ((sv_98 (parse-ctx-res-val ctx)))
            (let ((sp_107 (c99ds-typedef_name ctx env sp_97)))
                (if sp_107
                    (let ((sv_108 (parse-ctx-res-val ctx)))
                      (let ((sp_109 (let rloop_111 ((rcur_112 sp_107) (racc_113 '()))
                                (let ((rnext_114 (let ((sp_115 (c99ds-ws ctx env rcur_112)))
                                      (if sp_115
                                          (let ((sv_116 (parse-ctx-res-val ctx)))
                                            (let ((sp_117 (c99ds-decl_prefix ctx env sp_115)))
                                                (if sp_117
                                                    (let ((sv_118 (parse-ctx-res-val ctx)))
                                                      (begin
                                                          (parse-ctx-res-val-set! ctx (list sv_116 sv_118))
                                                          sp_117))
                                                    #f)))
                                          #f))))
                                  (if (and rnext_114 (> rnext_114 rcur_112))
                                      (rloop_111 rnext_114 (cons (parse-ctx-res-val ctx) racc_113))
                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_113)) rcur_112))))))
                          (if sp_109
                              (let ((sv_110 (parse-ctx-res-val ctx)))
                                (let ((sp_119 (c99ds-ws ctx env sp_109)))
                                    (if sp_119
                                        (let ((sv_120 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_98 sv_108 sv_110 sv_120))
                                              sp_119))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_121
          (c99ds-decorate-rule 'typedef_declaration_specifiers ctx env pos rdec_121 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: decl_prefix [memo]
(define (c99ds-decl_prefix ctx env pos)
  (peg-ds:rule-memo ctx 'decl_prefix pos
    (lambda ()
      (or
      (c99ds-storage_class_specifier ctx env pos)
      (c99ds-type_qualifier ctx env pos)
      (c99ds-function_specifier ctx env pos)
      (let ((sp_122 (peg-ds:lit ctx pos "__extension__" 13 #\_ "'__extension__'")))
          (if sp_122
              (let ((sv_123 (parse-ctx-res-val ctx)))
                (let ((sp_124 (let ((pred_126 (c99ds-ident_cont ctx env sp_122)))
                          (if pred_126
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_122)))))
                    (if sp_124
                        (let ((sv_125 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_123 sv_125))
                              sp_124))
                        #f)))
              #f))
      (c99ds-gnu_attribute ctx env pos)))))

;;; Rule: typeof_specifier [memo]
(define (c99ds-typeof_specifier ctx env pos)
  (peg-ds:rule-memo ctx 'typeof_specifier pos
    (lambda ()
      (let ((rdec_144 (let ((sp_127 (or
            (peg-ds:lit ctx pos "__typeof__" 10 #\_ "'__typeof__'")
            (peg-ds:lit ctx pos "__typeof" 8 #\_ "'__typeof'")
            (peg-ds:lit ctx pos "typeof" 6 #\t "'typeof'"))))
      (if sp_127
          (let ((sv_128 (parse-ctx-res-val ctx)))
            (let ((sp_129 (let ((pred_131 (c99ds-ident_cont ctx env sp_127)))
                      (if pred_131
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_127)))))
                (if sp_129
                    (let ((sv_130 (parse-ctx-res-val ctx)))
                      (let ((sp_132 (c99ds-ws ctx env sp_129)))
                          (if sp_132
                              (let ((sv_133 (parse-ctx-res-val ctx)))
                                (let ((sp_134 (peg-ds:lit1 ctx sp_132 #\( "(" "'('")))
                                    (if sp_134
                                        (let ((sv_135 (parse-ctx-res-val ctx)))
                                          (let ((sp_136 (c99ds-ws ctx env sp_134)))
                                              (if sp_136
                                                  (let ((sv_137 (parse-ctx-res-val ctx)))
                                                    (let ((sp_138 (or
                                                              (c99ds-type_name ctx env sp_136)
                                                              (c99ds-expr ctx env sp_136))))
                                                        (if sp_138
                                                            (let ((sv_139 (parse-ctx-res-val ctx)))
                                                              (let ((sp_140 (peg-ds:lit1 ctx sp_138 #\) ")" "')'")))
                                                                  (if sp_140
                                                                      (let ((sv_141 (parse-ctx-res-val ctx)))
                                                                        (let ((sp_142 (c99ds-ws ctx env sp_140)))
                                                                            (if sp_142
                                                                                (let ((sv_143 (parse-ctx-res-val ctx)))
                                                                                  (begin
                                                                                      (parse-ctx-res-val-set! ctx (list sv_128 sv_130 sv_133 sv_135 sv_137 sv_139 sv_141 sv_143))
                                                                                      sp_142))
                                                                                #f)))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_144
          (c99ds-decorate-rule 'typeof_specifier ctx env pos rdec_144 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: gnu_attribute [memo]
(define (c99ds-gnu_attribute ctx env pos)
  (peg-ds:rule-memo ctx 'gnu_attribute pos
    (lambda ()
      (let ((rdec_171 (let ((sp_145 (or
            (peg-ds:lit ctx pos "__attribute__" 13 #\_ "'__attribute__'")
            (peg-ds:lit ctx pos "__attribute" 11 #\_ "'__attribute'"))))
      (if sp_145
          (let ((sv_146 (parse-ctx-res-val ctx)))
            (let ((sp_147 (let ((pred_149 (c99ds-ident_cont ctx env sp_145)))
                      (if pred_149
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_145)))))
                (if sp_147
                    (let ((sv_148 (parse-ctx-res-val ctx)))
                      (let ((sp_150 (c99ds-ws ctx env sp_147)))
                          (if sp_150
                              (let ((sv_151 (parse-ctx-res-val ctx)))
                                (let ((sp_152 (peg-ds:lit1 ctx sp_150 #\( "(" "'('")))
                                    (if sp_152
                                        (let ((sv_153 (parse-ctx-res-val ctx)))
                                          (let ((sp_154 (c99ds-ws ctx env sp_152)))
                                              (if sp_154
                                                  (let ((sv_155 (parse-ctx-res-val ctx)))
                                                    (let ((sp_156 (peg-ds:lit1 ctx sp_154 #\( "(" "'('")))
                                                        (if sp_156
                                                            (let ((sv_157 (parse-ctx-res-val ctx)))
                                                              (let ((sp_158 (c99ds-ws ctx env sp_156)))
                                                                  (if sp_158
                                                                      (let ((sv_159 (parse-ctx-res-val ctx)))
                                                                        (let ((sp_160 (let ((opt_162 (c99ds-attr_arg_list ctx env sp_158)))
                                                                                  (if opt_162
                                                                                      opt_162
                                                                                      (begin (parse-ctx-res-val-set! ctx #f) sp_158)))))
                                                                            (if sp_160
                                                                                (let ((sv_161 (parse-ctx-res-val ctx)))
                                                                                  (let ((sp_163 (peg-ds:lit1 ctx sp_160 #\) ")" "')'")))
                                                                                      (if sp_163
                                                                                          (let ((sv_164 (parse-ctx-res-val ctx)))
                                                                                            (let ((sp_165 (c99ds-ws ctx env sp_163)))
                                                                                                (if sp_165
                                                                                                    (let ((sv_166 (parse-ctx-res-val ctx)))
                                                                                                      (let ((sp_167 (peg-ds:lit1 ctx sp_165 #\) ")" "')'")))
                                                                                                          (if sp_167
                                                                                                              (let ((sv_168 (parse-ctx-res-val ctx)))
                                                                                                                (let ((sp_169 (c99ds-ws ctx env sp_167)))
                                                                                                                    (if sp_169
                                                                                                                        (let ((sv_170 (parse-ctx-res-val ctx)))
                                                                                                                          (begin
                                                                                                                              (parse-ctx-res-val-set! ctx (list sv_146 sv_148 sv_151 sv_153 sv_155 sv_157 sv_159 sv_161 sv_164 sv_166 sv_168 sv_170))
                                                                                                                              sp_169))
                                                                                                                        #f)))
                                                                                                              #f)))
                                                                                                    #f)))
                                                                                          #f)))
                                                                                #f)))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_171
          (c99ds-decorate-rule 'gnu_attribute ctx env pos rdec_171 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: attr_arg_list [memo]
(define (c99ds-attr_arg_list ctx env pos)
  (peg-ds:rule-memo ctx 'attr_arg_list pos
    (lambda ()
      (let ((rdec_188 (let ((sp_172 (let ((np_174 (c99ds-attr_arg ctx env pos)))
            (if np_174
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_174)
                #f))))
      (if sp_172
          (let ((sv_173 (parse-ctx-res-val ctx)))
            (let ((sp_175 (let ((np_177 (let rloop_178 ((rcur_179 sp_172) (racc_180 '()))
                            (let ((rnext_181 (let ((sp_182 (peg-ds:lit1 ctx rcur_179 #\, "," "','")))
                                  (if sp_182
                                      (let ((sv_183 (parse-ctx-res-val ctx)))
                                        (let ((sp_184 (c99ds-ws ctx env sp_182)))
                                            (if sp_184
                                                (let ((sv_185 (parse-ctx-res-val ctx)))
                                                  (let ((sp_186 (c99ds-attr_arg ctx env sp_184)))
                                                      (if sp_186
                                                          (let ((sv_187 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_183 sv_185 sv_187))
                                                                sp_186))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_181 (> rnext_181 rcur_179))
                                  (rloop_178 rnext_181 (cons (parse-ctx-res-val ctx) racc_180))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_180)) rcur_179))))))
                      (if np_177
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_177)
                          #f))))
                (if sp_175
                    (let ((sv_176 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_173 sv_176))
                          sp_175))
                    #f)))
          #f))))
      (if rdec_188
          (c99ds-decorate-rule 'attr_arg_list ctx env pos rdec_188 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: attr_arg [memo]
(define (c99ds-attr_arg ctx env pos)
  (peg-ds:rule-memo ctx 'attr_arg pos
    (lambda ()
      (let ((rdec_195 (let ((rp1_193 (c99ds-attr_token ctx env pos)))
      (if rp1_193
          (let ((rv1_194 (parse-ctx-res-val ctx)))
            (if (<= rp1_193 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_194)) rp1_193)
                (let rloop_189 ((rcur_190 rp1_193) (racc_191 (list rv1_194)))
                  (let ((rnext_192 (c99ds-attr_token ctx env rcur_190)))
                    (if (and rnext_192 (> rnext_192 rcur_190))
                        (rloop_189 rnext_192 (cons (parse-ctx-res-val ctx) racc_191))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_191)) rcur_190))))))
          #f))))
      (if rdec_195
          (c99ds-decorate-rule 'attr_arg ctx env pos rdec_195 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: attr_token [memo]
(define (c99ds-attr_token ctx env pos)
  (peg-ds:rule-memo ctx 'attr_token pos
    (lambda ()
      (or
      (let ((sp_196 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_196
              (let ((sv_197 (parse-ctx-res-val ctx)))
                (let ((sp_198 (c99ds-ws ctx env sp_196)))
                    (if sp_198
                        (let ((sv_199 (parse-ctx-res-val ctx)))
                          (let ((sp_200 (let rloop_202 ((rcur_203 sp_198) (racc_204 '()))
                                    (let ((rnext_205 (c99ds-attr_balanced ctx env rcur_203)))
                                      (if (and rnext_205 (> rnext_205 rcur_203))
                                          (rloop_202 rnext_205 (cons (parse-ctx-res-val ctx) racc_204))
                                          (begin (parse-ctx-res-val-set! ctx (reverse racc_204)) rcur_203))))))
                              (if sp_200
                                  (let ((sv_201 (parse-ctx-res-val ctx)))
                                    (let ((sp_206 (peg-ds:lit1 ctx sp_200 #\) ")" "')'")))
                                        (if sp_206
                                            (let ((sv_207 (parse-ctx-res-val ctx)))
                                              (let ((sp_208 (c99ds-ws ctx env sp_206)))
                                                  (if sp_208
                                                      (let ((sv_209 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_197 sv_199 sv_201 sv_207 sv_209))
                                                            sp_208))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_210 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_210
              (let ((sv_211 (parse-ctx-res-val ctx)))
                (let ((sp_212 (c99ds-ws ctx env sp_210)))
                    (if sp_212
                        (let ((sv_213 (parse-ctx-res-val ctx)))
                          (let ((sp_214 (let rloop_216 ((rcur_217 sp_212) (racc_218 '()))
                                    (let ((rnext_219 (c99ds-attr_balanced ctx env rcur_217)))
                                      (if (and rnext_219 (> rnext_219 rcur_217))
                                          (rloop_216 rnext_219 (cons (parse-ctx-res-val ctx) racc_218))
                                          (begin (parse-ctx-res-val-set! ctx (reverse racc_218)) rcur_217))))))
                              (if sp_214
                                  (let ((sv_215 (parse-ctx-res-val ctx)))
                                    (let ((sp_220 (peg-ds:lit1 ctx sp_214 #\] "]" "']'")))
                                        (if sp_220
                                            (let ((sv_221 (parse-ctx-res-val ctx)))
                                              (let ((sp_222 (c99ds-ws ctx env sp_220)))
                                                  (if sp_222
                                                      (let ((sv_223 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_211 sv_213 sv_215 sv_221 sv_223))
                                                            sp_222))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_224 (c99ds-string_literal ctx env pos)))
          (if sp_224
              (let ((sv_225 (parse-ctx-res-val ctx)))
                (let ((sp_226 (c99ds-ws ctx env sp_224)))
                    (if sp_226
                        (let ((sv_227 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_225 sv_227))
                              sp_226))
                        #f)))
              #f))
      (let ((sp_228 (c99ds-constant ctx env pos)))
          (if sp_228
              (let ((sv_229 (parse-ctx-res-val ctx)))
                (let ((sp_230 (c99ds-ws ctx env sp_228)))
                    (if sp_230
                        (let ((sv_231 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_229 sv_231))
                              sp_230))
                        #f)))
              #f))
      (let ((sp_232 (c99ds-c99_keyword ctx env pos)))
          (if sp_232
              (let ((sv_233 (parse-ctx-res-val ctx)))
                (let ((sp_234 (c99ds-ws ctx env sp_232)))
                    (if sp_234
                        (let ((sv_235 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_233 sv_235))
                              sp_234))
                        #f)))
              #f))
      (let ((sp_236 (c99ds-identifier ctx env pos)))
          (if sp_236
              (let ((sv_237 (parse-ctx-res-val ctx)))
                (let ((sp_238 (c99ds-ws ctx env sp_236)))
                    (if sp_238
                        (let ((sv_239 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_237 sv_239))
                              sp_238))
                        #f)))
              #f))
      (let ((sp_240 (let ((pred_242 (or
                      (peg-ds:lit1 ctx pos #\( "(" "'('")
                      (peg-ds:lit1 ctx pos #\) ")" "')'")
                      (peg-ds:lit1 ctx pos #\[ "[" "'['")
                      (peg-ds:lit1 ctx pos #\] "]" "']'")
                      (peg-ds:lit1 ctx pos #\{ "{" "'{'")
                      (peg-ds:lit1 ctx pos #\} "}" "'}'")
                      (peg-ds:lit1 ctx pos #\, "," "','"))))
                (if pred_242
                    #f
                    (begin (parse-ctx-res-val-set! ctx #t) pos)))))
          (if sp_240
              (let ((sv_241 (parse-ctx-res-val ctx)))
                (let ((sp_243 (c99ds-c99_punctuator ctx env sp_240)))
                    (if sp_243
                        (let ((sv_244 (parse-ctx-res-val ctx)))
                          (let ((sp_245 (c99ds-ws ctx env sp_243)))
                              (if sp_245
                                  (let ((sv_246 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_241 sv_244 sv_246))
                                        sp_245))
                                  #f)))
                        #f)))
              #f))))))

;;; Rule: attr_balanced [memo]
(define (c99ds-attr_balanced ctx env pos)
  (peg-ds:rule-memo ctx 'attr_balanced pos
    (lambda ()
      (or
      (let ((sp_247 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_247
              (let ((sv_248 (parse-ctx-res-val ctx)))
                (let ((sp_249 (c99ds-ws ctx env sp_247)))
                    (if sp_249
                        (let ((sv_250 (parse-ctx-res-val ctx)))
                          (let ((sp_251 (let rloop_253 ((rcur_254 sp_249) (racc_255 '()))
                                    (let ((rnext_256 (c99ds-attr_balanced ctx env rcur_254)))
                                      (if (and rnext_256 (> rnext_256 rcur_254))
                                          (rloop_253 rnext_256 (cons (parse-ctx-res-val ctx) racc_255))
                                          (begin (parse-ctx-res-val-set! ctx (reverse racc_255)) rcur_254))))))
                              (if sp_251
                                  (let ((sv_252 (parse-ctx-res-val ctx)))
                                    (let ((sp_257 (peg-ds:lit1 ctx sp_251 #\) ")" "')'")))
                                        (if sp_257
                                            (let ((sv_258 (parse-ctx-res-val ctx)))
                                              (let ((sp_259 (c99ds-ws ctx env sp_257)))
                                                  (if sp_259
                                                      (let ((sv_260 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_248 sv_250 sv_252 sv_258 sv_260))
                                                            sp_259))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_261 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_261
              (let ((sv_262 (parse-ctx-res-val ctx)))
                (let ((sp_263 (c99ds-ws ctx env sp_261)))
                    (if sp_263
                        (let ((sv_264 (parse-ctx-res-val ctx)))
                          (let ((sp_265 (let rloop_267 ((rcur_268 sp_263) (racc_269 '()))
                                    (let ((rnext_270 (c99ds-attr_balanced ctx env rcur_268)))
                                      (if (and rnext_270 (> rnext_270 rcur_268))
                                          (rloop_267 rnext_270 (cons (parse-ctx-res-val ctx) racc_269))
                                          (begin (parse-ctx-res-val-set! ctx (reverse racc_269)) rcur_268))))))
                              (if sp_265
                                  (let ((sv_266 (parse-ctx-res-val ctx)))
                                    (let ((sp_271 (peg-ds:lit1 ctx sp_265 #\] "]" "']'")))
                                        (if sp_271
                                            (let ((sv_272 (parse-ctx-res-val ctx)))
                                              (let ((sp_273 (c99ds-ws ctx env sp_271)))
                                                  (if sp_273
                                                      (let ((sv_274 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_262 sv_264 sv_266 sv_272 sv_274))
                                                            sp_273))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_275 (c99ds-string_literal ctx env pos)))
          (if sp_275
              (let ((sv_276 (parse-ctx-res-val ctx)))
                (let ((sp_277 (c99ds-ws ctx env sp_275)))
                    (if sp_277
                        (let ((sv_278 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_276 sv_278))
                              sp_277))
                        #f)))
              #f))
      (let ((sp_279 (c99ds-constant ctx env pos)))
          (if sp_279
              (let ((sv_280 (parse-ctx-res-val ctx)))
                (let ((sp_281 (c99ds-ws ctx env sp_279)))
                    (if sp_281
                        (let ((sv_282 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_280 sv_282))
                              sp_281))
                        #f)))
              #f))
      (let ((sp_283 (c99ds-c99_keyword ctx env pos)))
          (if sp_283
              (let ((sv_284 (parse-ctx-res-val ctx)))
                (let ((sp_285 (c99ds-ws ctx env sp_283)))
                    (if sp_285
                        (let ((sv_286 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_284 sv_286))
                              sp_285))
                        #f)))
              #f))
      (let ((sp_287 (c99ds-identifier ctx env pos)))
          (if sp_287
              (let ((sv_288 (parse-ctx-res-val ctx)))
                (let ((sp_289 (c99ds-ws ctx env sp_287)))
                    (if sp_289
                        (let ((sv_290 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_288 sv_290))
                              sp_289))
                        #f)))
              #f))
      (let ((sp_291 (peg-ds:lit1 ctx pos #\, "," "','")))
          (if sp_291
              (let ((sv_292 (parse-ctx-res-val ctx)))
                (let ((sp_293 (c99ds-ws ctx env sp_291)))
                    (if sp_293
                        (let ((sv_294 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_292 sv_294))
                              sp_293))
                        #f)))
              #f))
      (let ((sp_295 (let ((pred_297 (or
                      (peg-ds:lit1 ctx pos #\( "(" "'('")
                      (peg-ds:lit1 ctx pos #\) ")" "')'")
                      (peg-ds:lit1 ctx pos #\[ "[" "'['")
                      (peg-ds:lit1 ctx pos #\] "]" "']'")
                      (peg-ds:lit1 ctx pos #\{ "{" "'{'")
                      (peg-ds:lit1 ctx pos #\} "}" "'}'")
                      (peg-ds:lit1 ctx pos #\, "," "','"))))
                (if pred_297
                    #f
                    (begin (parse-ctx-res-val-set! ctx #t) pos)))))
          (if sp_295
              (let ((sv_296 (parse-ctx-res-val ctx)))
                (let ((sp_298 (c99ds-c99_punctuator ctx env sp_295)))
                    (if sp_298
                        (let ((sv_299 (parse-ctx-res-val ctx)))
                          (let ((sp_300 (c99ds-ws ctx env sp_298)))
                              (if sp_300
                                  (let ((sv_301 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_296 sv_299 sv_301))
                                        sp_300))
                                  #f)))
                        #f)))
              #f))))))

;;; Rule: decl_asm_label [bare]
(define (c99ds-decl_asm_label ctx env pos)
  (let ((rdec_319 (let ((sp_302 (or
            (peg-ds:lit ctx pos "__asm__" 7 #\_ "'__asm__'")
            (peg-ds:lit ctx pos "__asm" 5 #\_ "'__asm'")
            (peg-ds:lit ctx pos "asm" 3 #\a "'asm'"))))
      (if sp_302
          (let ((sv_303 (parse-ctx-res-val ctx)))
            (let ((sp_304 (let ((pred_306 (c99ds-ident_cont ctx env sp_302)))
                      (if pred_306
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_302)))))
                (if sp_304
                    (let ((sv_305 (parse-ctx-res-val ctx)))
                      (let ((sp_307 (c99ds-ws ctx env sp_304)))
                          (if sp_307
                              (let ((sv_308 (parse-ctx-res-val ctx)))
                                (let ((sp_309 (peg-ds:lit1 ctx sp_307 #\( "(" "'('")))
                                    (if sp_309
                                        (let ((sv_310 (parse-ctx-res-val ctx)))
                                          (let ((sp_311 (c99ds-ws ctx env sp_309)))
                                              (if sp_311
                                                  (let ((sv_312 (parse-ctx-res-val ctx)))
                                                    (let ((sp_313 (c99ds-asm_template ctx env sp_311)))
                                                        (if sp_313
                                                            (let ((sv_314 (parse-ctx-res-val ctx)))
                                                              (let ((sp_315 (peg-ds:lit1 ctx sp_313 #\) ")" "')'")))
                                                                  (if sp_315
                                                                      (let ((sv_316 (parse-ctx-res-val ctx)))
                                                                        (let ((sp_317 (c99ds-ws ctx env sp_315)))
                                                                            (if sp_317
                                                                                (let ((sv_318 (parse-ctx-res-val ctx)))
                                                                                  (begin
                                                                                      (parse-ctx-res-val-set! ctx (list sv_303 sv_305 sv_308 sv_310 sv_312 sv_314 sv_316 sv_318))
                                                                                      sp_317))
                                                                                #f)))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_319
          (c99ds-decorate-rule 'decl_asm_label ctx env pos rdec_319 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: init_declarator_list [memo]
(define (c99ds-init_declarator_list ctx env pos)
  (peg-ds:rule-memo ctx 'init_declarator_list pos
    (lambda ()
      (let ((rdec_336 (let ((sp_320 (let ((np_322 (c99ds-init_declarator ctx env pos)))
            (if np_322
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_322)
                #f))))
      (if sp_320
          (let ((sv_321 (parse-ctx-res-val ctx)))
            (let ((sp_323 (let ((np_325 (let rloop_326 ((rcur_327 sp_320) (racc_328 '()))
                            (let ((rnext_329 (let ((sp_330 (peg-ds:lit1 ctx rcur_327 #\, "," "','")))
                                  (if sp_330
                                      (let ((sv_331 (parse-ctx-res-val ctx)))
                                        (let ((sp_332 (c99ds-ws ctx env sp_330)))
                                            (if sp_332
                                                (let ((sv_333 (parse-ctx-res-val ctx)))
                                                  (let ((sp_334 (c99ds-init_declarator ctx env sp_332)))
                                                      (if sp_334
                                                          (let ((sv_335 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_331 sv_333 sv_335))
                                                                sp_334))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_329 (> rnext_329 rcur_327))
                                  (rloop_326 rnext_329 (cons (parse-ctx-res-val ctx) racc_328))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_328)) rcur_327))))))
                      (if np_325
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_325)
                          #f))))
                (if sp_323
                    (let ((sv_324 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_321 sv_324))
                          sp_323))
                    #f)))
          #f))))
      (if rdec_336
          (c99ds-decorate-rule 'init_declarator_list ctx env pos rdec_336 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: typedef_init_declarator_list [memo]
(define (c99ds-typedef_init_declarator_list ctx env pos)
  (peg-ds:rule-memo ctx 'typedef_init_declarator_list pos
    (lambda ()
      (let ((rdec_353 (let ((sp_337 (let ((np_339 (c99ds-typedef_init_declarator ctx env pos)))
            (if np_339
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_339)
                #f))))
      (if sp_337
          (let ((sv_338 (parse-ctx-res-val ctx)))
            (let ((sp_340 (let ((np_342 (let rloop_343 ((rcur_344 sp_337) (racc_345 '()))
                            (let ((rnext_346 (let ((sp_347 (peg-ds:lit1 ctx rcur_344 #\, "," "','")))
                                  (if sp_347
                                      (let ((sv_348 (parse-ctx-res-val ctx)))
                                        (let ((sp_349 (c99ds-ws ctx env sp_347)))
                                            (if sp_349
                                                (let ((sv_350 (parse-ctx-res-val ctx)))
                                                  (let ((sp_351 (c99ds-init_declarator ctx env sp_349)))
                                                      (if sp_351
                                                          (let ((sv_352 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_348 sv_350 sv_352))
                                                                sp_351))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_346 (> rnext_346 rcur_344))
                                  (rloop_343 rnext_346 (cons (parse-ctx-res-val ctx) racc_345))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_345)) rcur_344))))))
                      (if np_342
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_342)
                          #f))))
                (if sp_340
                    (let ((sv_341 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_338 sv_341))
                          sp_340))
                    #f)))
          #f))))
      (if rdec_353
          (c99ds-decorate-rule 'typedef_init_declarator_list ctx env pos rdec_353 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: init_declarator [memo]
(define (c99ds-init_declarator ctx env pos)
  (peg-ds:rule-memo ctx 'init_declarator pos
    (lambda ()
      (let ((rdec_374 (let ((sp_354 (c99ds-declarator ctx env pos)))
      (if sp_354
          (let ((sv_355 (parse-ctx-res-val ctx)))
            (let ((sp_356 (let ((opt_358 (c99ds-decl_asm_label ctx env sp_354)))
                      (if opt_358
                          opt_358
                          (begin (parse-ctx-res-val-set! ctx #f) sp_354)))))
                (if sp_356
                    (let ((sv_357 (parse-ctx-res-val ctx)))
                      (let ((sp_359 (let rloop_361 ((rcur_362 sp_356) (racc_363 '()))
                                (let ((rnext_364 (c99ds-gnu_attribute ctx env rcur_362)))
                                  (if (and rnext_364 (> rnext_364 rcur_362))
                                      (rloop_361 rnext_364 (cons (parse-ctx-res-val ctx) racc_363))
                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_363)) rcur_362))))))
                          (if sp_359
                              (let ((sv_360 (parse-ctx-res-val ctx)))
                                (let ((sp_365 (let ((opt_367 (let ((sp_368 (peg-ds:lit1 ctx sp_359 #\= "=" "'='")))
                                                (if sp_368
                                                    (let ((sv_369 (parse-ctx-res-val ctx)))
                                                      (let ((sp_370 (c99ds-ws ctx env sp_368)))
                                                          (if sp_370
                                                              (let ((sv_371 (parse-ctx-res-val ctx)))
                                                                (let ((sp_372 (c99ds-initializer ctx env sp_370)))
                                                                    (if sp_372
                                                                        (let ((sv_373 (parse-ctx-res-val ctx)))
                                                                          (begin
                                                                              (parse-ctx-res-val-set! ctx (list sv_369 sv_371 sv_373))
                                                                              sp_372))
                                                                        #f)))
                                                              #f)))
                                                    #f))))
                                          (if opt_367
                                              opt_367
                                              (begin (parse-ctx-res-val-set! ctx #f) sp_359)))))
                                    (if sp_365
                                        (let ((sv_366 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_355 sv_357 sv_360 sv_366))
                                              sp_365))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_374
          (c99ds-decorate-rule 'init_declarator ctx env pos rdec_374 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: typedef_init_declarator [bare]
(define (c99ds-typedef_init_declarator ctx env pos)
  (c99ds-override-typedef-init-declarator ctx env pos))

;;; Rule: storage_class_specifier [bare]
(define (c99ds-storage_class_specifier ctx env pos)
  (let ((rdec_380 (let ((sp_375 (or
            (peg-ds:lit ctx pos "typedef" 7 #\t "'typedef'")
            (peg-ds:lit ctx pos "extern" 6 #\e "'extern'")
            (peg-ds:lit ctx pos "static" 6 #\s "'static'")
            (peg-ds:lit ctx pos "auto" 4 #\a "'auto'")
            (peg-ds:lit ctx pos "register" 8 #\r "'register'"))))
      (if sp_375
          (let ((sv_376 (parse-ctx-res-val ctx)))
            (let ((sp_377 (let ((pred_379 (c99ds-ident_cont ctx env sp_375)))
                      (if pred_379
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_375)))))
                (if sp_377
                    (let ((sv_378 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_376 sv_378))
                          sp_377))
                    #f)))
          #f))))
      (if rdec_380
          (c99ds-decorate-rule 'storage_class_specifier ctx env pos rdec_380 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: builtin_type_specifier [bare]
(define (c99ds-builtin_type_specifier ctx env pos)
  (let ((rdec_386 (let ((sp_381 (or
            (peg-ds:lit ctx pos "void" 4 #\v "'void'")
            (peg-ds:lit ctx pos "char" 4 #\c "'char'")
            (peg-ds:lit ctx pos "short" 5 #\s "'short'")
            (peg-ds:lit ctx pos "int" 3 #\i "'int'")
            (peg-ds:lit ctx pos "long" 4 #\l "'long'")
            (peg-ds:lit ctx pos "float" 5 #\f "'float'")
            (peg-ds:lit ctx pos "double" 6 #\d "'double'")
            (peg-ds:lit ctx pos "__signed__" 10 #\_ "'__signed__'")
            (peg-ds:lit ctx pos "__signed" 8 #\_ "'__signed'")
            (peg-ds:lit ctx pos "signed" 6 #\s "'signed'")
            (peg-ds:lit ctx pos "unsigned" 8 #\u "'unsigned'")
            (peg-ds:lit ctx pos "_Bool" 5 #\_ "'_Bool'")
            (peg-ds:lit ctx pos "_Complex" 8 #\_ "'_Complex'")
            (peg-ds:lit ctx pos "_Imaginary" 10 #\_ "'_Imaginary'"))))
      (if sp_381
          (let ((sv_382 (parse-ctx-res-val ctx)))
            (let ((sp_383 (let ((pred_385 (c99ds-ident_cont ctx env sp_381)))
                      (if pred_385
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_381)))))
                (if sp_383
                    (let ((sv_384 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_382 sv_384))
                          sp_383))
                    #f)))
          #f))))
      (if rdec_386
          (c99ds-decorate-rule 'builtin_type_specifier ctx env pos rdec_386 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: type_qualifier [bare]
(define (c99ds-type_qualifier ctx env pos)
  (let ((rdec_392 (let ((sp_387 (or
            (peg-ds:lit ctx pos "__const__" 9 #\_ "'__const__'")
            (peg-ds:lit ctx pos "__const" 7 #\_ "'__const'")
            (peg-ds:lit ctx pos "const" 5 #\c "'const'")
            (peg-ds:lit ctx pos "__restrict__" 12 #\_ "'__restrict__'")
            (peg-ds:lit ctx pos "__restrict" 10 #\_ "'__restrict'")
            (peg-ds:lit ctx pos "restrict" 8 #\r "'restrict'")
            (peg-ds:lit ctx pos "__volatile__" 12 #\_ "'__volatile__'")
            (peg-ds:lit ctx pos "__volatile" 10 #\_ "'__volatile'")
            (peg-ds:lit ctx pos "volatile" 8 #\v "'volatile'"))))
      (if sp_387
          (let ((sv_388 (parse-ctx-res-val ctx)))
            (let ((sp_389 (let ((pred_391 (c99ds-ident_cont ctx env sp_387)))
                      (if pred_391
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_387)))))
                (if sp_389
                    (let ((sv_390 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_388 sv_390))
                          sp_389))
                    #f)))
          #f))))
      (if rdec_392
          (c99ds-decorate-rule 'type_qualifier ctx env pos rdec_392 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: function_specifier [bare]
(define (c99ds-function_specifier ctx env pos)
  (let ((rdec_398 (let ((sp_393 (or
            (peg-ds:lit ctx pos "__inline__" 10 #\_ "'__inline__'")
            (peg-ds:lit ctx pos "__inline" 8 #\_ "'__inline'")
            (peg-ds:lit ctx pos "inline" 6 #\i "'inline'"))))
      (if sp_393
          (let ((sv_394 (parse-ctx-res-val ctx)))
            (let ((sp_395 (let ((pred_397 (c99ds-ident_cont ctx env sp_393)))
                      (if pred_397
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_393)))))
                (if sp_395
                    (let ((sv_396 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_394 sv_396))
                          sp_395))
                    #f)))
          #f))))
      (if rdec_398
          (c99ds-decorate-rule 'function_specifier ctx env pos rdec_398 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: aggregate_or_enum_specifier [memo]
(define (c99ds-aggregate_or_enum_specifier ctx env pos)
  (peg-ds:rule-memo ctx 'aggregate_or_enum_specifier pos
    (lambda ()
      (or
      (c99ds-struct_or_union_specifier ctx env pos)
      (c99ds-enum_specifier ctx env pos)))))

;;; Rule: struct_or_union_specifier [memo]
(define (c99ds-struct_or_union_specifier ctx env pos)
  (peg-ds:rule-memo ctx 'struct_or_union_specifier pos
    (lambda ()
      (let ((rdec_429 (or
      (let ((sp_399 (c99ds-struct_or_union ctx env pos)))
          (if sp_399
              (let ((sv_400 (parse-ctx-res-val ctx)))
                (let ((sp_401 (c99ds-ws ctx env sp_399)))
                    (if sp_401
                        (let ((sv_402 (parse-ctx-res-val ctx)))
                          (let ((sp_403 (let ((opt_405 (c99ds-identifier ctx env sp_401)))
                                    (if opt_405
                                        opt_405
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_401)))))
                              (if sp_403
                                  (let ((sv_404 (parse-ctx-res-val ctx)))
                                    (let ((sp_406 (c99ds-ws ctx env sp_403)))
                                        (if sp_406
                                            (let ((sv_407 (parse-ctx-res-val ctx)))
                                              (let ((sp_408 (peg-ds:lit1 ctx sp_406 #\{ "{" "'{'")))
                                                  (if sp_408
                                                      (let ((sv_409 (parse-ctx-res-val ctx)))
                                                        (let ((sp_410 (c99ds-ws ctx env sp_408)))
                                                            (if sp_410
                                                                (let ((sv_411 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_412 (let ((opt_414 (c99ds-struct_declaration_list ctx env sp_410)))
                                                                            (if opt_414
                                                                                opt_414
                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_410)))))
                                                                      (if sp_412
                                                                          (let ((sv_413 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_415 (c99ds-ws ctx env sp_412)))
                                                                                (if sp_415
                                                                                    (let ((sv_416 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_417 (peg-ds:lit1 ctx sp_415 #\} "}" "'}'")))
                                                                                          (if sp_417
                                                                                              (let ((sv_418 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_419 (c99ds-ws ctx env sp_417)))
                                                                                                    (if sp_419
                                                                                                        (let ((sv_420 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_400 sv_402 sv_404 sv_407 sv_409 sv_411 sv_413 sv_416 sv_418 sv_420))
                                                                                                              sp_419))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_421 (c99ds-struct_or_union ctx env pos)))
          (if sp_421
              (let ((sv_422 (parse-ctx-res-val ctx)))
                (let ((sp_423 (c99ds-ws ctx env sp_421)))
                    (if sp_423
                        (let ((sv_424 (parse-ctx-res-val ctx)))
                          (let ((sp_425 (c99ds-identifier ctx env sp_423)))
                              (if sp_425
                                  (let ((sv_426 (parse-ctx-res-val ctx)))
                                    (let ((sp_427 (c99ds-ws ctx env sp_425)))
                                        (if sp_427
                                            (let ((sv_428 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_422 sv_424 sv_426 sv_428))
                                                  sp_427))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_429
          (c99ds-decorate-rule 'struct_or_union_specifier ctx env pos rdec_429 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: struct_or_union [bare]
(define (c99ds-struct_or_union ctx env pos)
  (let ((rdec_435 (let ((sp_430 (or
            (peg-ds:lit ctx pos "struct" 6 #\s "'struct'")
            (peg-ds:lit ctx pos "union" 5 #\u "'union'"))))
      (if sp_430
          (let ((sv_431 (parse-ctx-res-val ctx)))
            (let ((sp_432 (let ((pred_434 (c99ds-ident_cont ctx env sp_430)))
                      (if pred_434
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_430)))))
                (if sp_432
                    (let ((sv_433 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_431 sv_433))
                          sp_432))
                    #f)))
          #f))))
      (if rdec_435
          (c99ds-decorate-rule 'struct_or_union ctx env pos rdec_435 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: struct_declaration_list [memo]
(define (c99ds-struct_declaration_list ctx env pos)
  (peg-ds:rule-memo ctx 'struct_declaration_list pos
    (lambda ()
      (let ((rp1_440 (c99ds-struct_declaration ctx env pos)))
      (if rp1_440
          (let ((rv1_441 (parse-ctx-res-val ctx)))
            (if (<= rp1_440 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_441)) rp1_440)
                (let rloop_436 ((rcur_437 rp1_440) (racc_438 (list rv1_441)))
                  (let ((rnext_439 (c99ds-struct_declaration ctx env rcur_437)))
                    (if (and rnext_439 (> rnext_439 rcur_437))
                        (rloop_436 rnext_439 (cons (parse-ctx-res-val ctx) racc_438))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_438)) rcur_437))))))
          #f)))))

;;; Rule: struct_declaration [memo]
(define (c99ds-struct_declaration ctx env pos)
  (peg-ds:rule-memo ctx 'struct_declaration pos
    (lambda ()
      (let ((rdec_451 (let ((sp_442 (c99ds-specifier_qualifier_list ctx env pos)))
      (if sp_442
          (let ((sv_443 (parse-ctx-res-val ctx)))
            (let ((sp_444 (let ((opt_446 (c99ds-struct_declarator_list ctx env sp_442)))
                      (if opt_446
                          opt_446
                          (begin (parse-ctx-res-val-set! ctx #f) sp_442)))))
                (if sp_444
                    (let ((sv_445 (parse-ctx-res-val ctx)))
                      (let ((sp_447 (peg-ds:lit1 ctx sp_444 #\; ";" "';'")))
                          (if sp_447
                              (let ((sv_448 (parse-ctx-res-val ctx)))
                                (let ((sp_449 (c99ds-ws ctx env sp_447)))
                                    (if sp_449
                                        (let ((sv_450 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_443 sv_445 sv_448 sv_450))
                                              sp_449))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_451
          (c99ds-decorate-rule 'struct_declaration ctx env pos rdec_451 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: specifier_qualifier_list [memo]
(define (c99ds-specifier_qualifier_list ctx env pos)
  (peg-ds:rule-memo ctx 'specifier_qualifier_list pos
    (lambda ()
      (let ((rdec_516 (or
      (let ((sp_452 (let rloop_454 ((rcur_455 pos) (racc_456 '()))
                (let ((rnext_457 (or
                      (let ((sp_458 (c99ds-type_qualifier ctx env rcur_455)))
                          (if sp_458
                              (let ((sv_459 (parse-ctx-res-val ctx)))
                                (let ((sp_460 (c99ds-ws ctx env sp_458)))
                                    (if sp_460
                                        (let ((sv_461 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_459 sv_461))
                                              sp_460))
                                        #f)))
                              #f))
                      (c99ds-gnu_attribute ctx env rcur_455))))
                  (if (and rnext_457 (> rnext_457 rcur_455))
                      (rloop_454 rnext_457 (cons (parse-ctx-res-val ctx) racc_456))
                      (begin (parse-ctx-res-val-set! ctx (reverse racc_456)) rcur_455))))))
          (if sp_452
              (let ((sv_453 (parse-ctx-res-val ctx)))
                (let ((sp_462 (or
                          (let ((sp_464 (c99ds-builtin_type_specifier ctx env sp_452)))
                              (if sp_464
                                  (let ((sv_465 (parse-ctx-res-val ctx)))
                                    (let ((sp_466 (let rloop_468 ((rcur_469 sp_464) (racc_470 '()))
                                              (let ((rnext_471 (let ((sp_472 (c99ds-ws ctx env rcur_469)))
                                                    (if sp_472
                                                        (let ((sv_473 (parse-ctx-res-val ctx)))
                                                          (let ((sp_474 (or
                                                                    (c99ds-type_qualifier ctx env sp_472)
                                                                    (c99ds-builtin_type_specifier ctx env sp_472)
                                                                    (c99ds-gnu_attribute ctx env sp_472))))
                                                              (if sp_474
                                                                  (let ((sv_475 (parse-ctx-res-val ctx)))
                                                                    (begin
                                                                        (parse-ctx-res-val-set! ctx (list sv_473 sv_475))
                                                                        sp_474))
                                                                  #f)))
                                                        #f))))
                                                (if (and rnext_471 (> rnext_471 rcur_469))
                                                    (rloop_468 rnext_471 (cons (parse-ctx-res-val ctx) racc_470))
                                                    (begin (parse-ctx-res-val-set! ctx (reverse racc_470)) rcur_469))))))
                                        (if sp_466
                                            (let ((sv_467 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_465 sv_467))
                                                  sp_466))
                                            #f)))
                                  #f))
                          (let ((sp_476 (or
                                    (c99ds-aggregate_or_enum_specifier ctx env sp_452)
                                    (c99ds-typeof_specifier ctx env sp_452))))
                              (if sp_476
                                  (let ((sv_477 (parse-ctx-res-val ctx)))
                                    (let ((sp_478 (let rloop_480 ((rcur_481 sp_476) (racc_482 '()))
                                              (let ((rnext_483 (let ((sp_484 (c99ds-ws ctx env rcur_481)))
                                                    (if sp_484
                                                        (let ((sv_485 (parse-ctx-res-val ctx)))
                                                          (let ((sp_486 (or
                                                                    (c99ds-type_qualifier ctx env sp_484)
                                                                    (c99ds-gnu_attribute ctx env sp_484))))
                                                              (if sp_486
                                                                  (let ((sv_487 (parse-ctx-res-val ctx)))
                                                                    (begin
                                                                        (parse-ctx-res-val-set! ctx (list sv_485 sv_487))
                                                                        sp_486))
                                                                  #f)))
                                                        #f))))
                                                (if (and rnext_483 (> rnext_483 rcur_481))
                                                    (rloop_480 rnext_483 (cons (parse-ctx-res-val ctx) racc_482))
                                                    (begin (parse-ctx-res-val-set! ctx (reverse racc_482)) rcur_481))))))
                                        (if sp_478
                                            (let ((sv_479 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_477 sv_479))
                                                  sp_478))
                                            #f)))
                                  #f))
                          (let ((sp_488 (c99ds-typedef_name ctx env sp_452)))
                              (if sp_488
                                  (let ((sv_489 (parse-ctx-res-val ctx)))
                                    (let ((sp_490 (let rloop_492 ((rcur_493 sp_488) (racc_494 '()))
                                              (let ((rnext_495 (let ((sp_496 (c99ds-ws ctx env rcur_493)))
                                                    (if sp_496
                                                        (let ((sv_497 (parse-ctx-res-val ctx)))
                                                          (let ((sp_498 (or
                                                                    (c99ds-type_qualifier ctx env sp_496)
                                                                    (c99ds-gnu_attribute ctx env sp_496))))
                                                              (if sp_498
                                                                  (let ((sv_499 (parse-ctx-res-val ctx)))
                                                                    (begin
                                                                        (parse-ctx-res-val-set! ctx (list sv_497 sv_499))
                                                                        sp_498))
                                                                  #f)))
                                                        #f))))
                                                (if (and rnext_495 (> rnext_495 rcur_493))
                                                    (rloop_492 rnext_495 (cons (parse-ctx-res-val ctx) racc_494))
                                                    (begin (parse-ctx-res-val-set! ctx (reverse racc_494)) rcur_493))))))
                                        (if sp_490
                                            (let ((sv_491 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_489 sv_491))
                                                  sp_490))
                                            #f)))
                                  #f)))))
                    (if sp_462
                        (let ((sv_463 (parse-ctx-res-val ctx)))
                          (let ((sp_500 (c99ds-ws ctx env sp_462)))
                              (if sp_500
                                  (let ((sv_501 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_453 sv_463 sv_501))
                                        sp_500))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_502 (or
                (c99ds-type_qualifier ctx env pos)
                (c99ds-gnu_attribute ctx env pos))))
          (if sp_502
              (let ((sv_503 (parse-ctx-res-val ctx)))
                (let ((sp_504 (let rloop_506 ((rcur_507 sp_502) (racc_508 '()))
                          (let ((rnext_509 (let ((sp_510 (c99ds-ws ctx env rcur_507)))
                                (if sp_510
                                    (let ((sv_511 (parse-ctx-res-val ctx)))
                                      (let ((sp_512 (or
                                                (c99ds-type_qualifier ctx env sp_510)
                                                (c99ds-gnu_attribute ctx env sp_510))))
                                          (if sp_512
                                              (let ((sv_513 (parse-ctx-res-val ctx)))
                                                (begin
                                                    (parse-ctx-res-val-set! ctx (list sv_511 sv_513))
                                                    sp_512))
                                              #f)))
                                    #f))))
                            (if (and rnext_509 (> rnext_509 rcur_507))
                                (rloop_506 rnext_509 (cons (parse-ctx-res-val ctx) racc_508))
                                (begin (parse-ctx-res-val-set! ctx (reverse racc_508)) rcur_507))))))
                    (if sp_504
                        (let ((sv_505 (parse-ctx-res-val ctx)))
                          (let ((sp_514 (c99ds-ws ctx env sp_504)))
                              (if sp_514
                                  (let ((sv_515 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_503 sv_505 sv_515))
                                        sp_514))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_516
          (c99ds-decorate-rule 'specifier_qualifier_list ctx env pos rdec_516 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: struct_declarator_list [memo]
(define (c99ds-struct_declarator_list ctx env pos)
  (peg-ds:rule-memo ctx 'struct_declarator_list pos
    (lambda ()
      (let ((rdec_533 (let ((sp_517 (let ((np_519 (c99ds-struct_declarator ctx env pos)))
            (if np_519
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_519)
                #f))))
      (if sp_517
          (let ((sv_518 (parse-ctx-res-val ctx)))
            (let ((sp_520 (let ((np_522 (let rloop_523 ((rcur_524 sp_517) (racc_525 '()))
                            (let ((rnext_526 (let ((sp_527 (peg-ds:lit1 ctx rcur_524 #\, "," "','")))
                                  (if sp_527
                                      (let ((sv_528 (parse-ctx-res-val ctx)))
                                        (let ((sp_529 (c99ds-ws ctx env sp_527)))
                                            (if sp_529
                                                (let ((sv_530 (parse-ctx-res-val ctx)))
                                                  (let ((sp_531 (c99ds-struct_declarator ctx env sp_529)))
                                                      (if sp_531
                                                          (let ((sv_532 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_528 sv_530 sv_532))
                                                                sp_531))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_526 (> rnext_526 rcur_524))
                                  (rloop_523 rnext_526 (cons (parse-ctx-res-val ctx) racc_525))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_525)) rcur_524))))))
                      (if np_522
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_522)
                          #f))))
                (if sp_520
                    (let ((sv_521 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_518 sv_521))
                          sp_520))
                    #f)))
          #f))))
      (if rdec_533
          (c99ds-decorate-rule 'struct_declarator_list ctx env pos rdec_533 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: struct_declarator [memo]
(define (c99ds-struct_declarator ctx env pos)
  (peg-ds:rule-memo ctx 'struct_declarator pos
    (lambda ()
      (let ((rdec_557 (or
      (let ((sp_534 (let ((opt_536 (c99ds-declarator ctx env pos)))
                (if opt_536
                    opt_536
                    (begin (parse-ctx-res-val-set! ctx #f) pos)))))
          (if sp_534
              (let ((sv_535 (parse-ctx-res-val ctx)))
                (let ((sp_537 (peg-ds:lit1 ctx sp_534 #\: ":" "':'")))
                    (if sp_537
                        (let ((sv_538 (parse-ctx-res-val ctx)))
                          (let ((sp_539 (c99ds-ws ctx env sp_537)))
                              (if sp_539
                                  (let ((sv_540 (parse-ctx-res-val ctx)))
                                    (let ((sp_541 (c99ds-constant_expr ctx env sp_539)))
                                        (if sp_541
                                            (let ((sv_542 (parse-ctx-res-val ctx)))
                                              (let ((sp_543 (let rloop_545 ((rcur_546 sp_541) (racc_547 '()))
                                                        (let ((rnext_548 (c99ds-gnu_attribute ctx env rcur_546)))
                                                          (if (and rnext_548 (> rnext_548 rcur_546))
                                                              (rloop_545 rnext_548 (cons (parse-ctx-res-val ctx) racc_547))
                                                              (begin (parse-ctx-res-val-set! ctx (reverse racc_547)) rcur_546))))))
                                                  (if sp_543
                                                      (let ((sv_544 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_535 sv_538 sv_540 sv_542 sv_544))
                                                            sp_543))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_549 (c99ds-declarator ctx env pos)))
          (if sp_549
              (let ((sv_550 (parse-ctx-res-val ctx)))
                (let ((sp_551 (let rloop_553 ((rcur_554 sp_549) (racc_555 '()))
                          (let ((rnext_556 (c99ds-gnu_attribute ctx env rcur_554)))
                            (if (and rnext_556 (> rnext_556 rcur_554))
                                (rloop_553 rnext_556 (cons (parse-ctx-res-val ctx) racc_555))
                                (begin (parse-ctx-res-val-set! ctx (reverse racc_555)) rcur_554))))))
                    (if sp_551
                        (let ((sv_552 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_550 sv_552))
                              sp_551))
                        #f)))
              #f)))))
      (if rdec_557
          (c99ds-decorate-rule 'struct_declarator ctx env pos rdec_557 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: enum_specifier [memo]
(define (c99ds-enum_specifier ctx env pos)
  (peg-ds:rule-memo ctx 'enum_specifier pos
    (lambda ()
      (let ((rdec_598 (or
      (let ((sp_558 (peg-ds:lit ctx pos "enum" 4 #\e "'enum'")))
          (if sp_558
              (let ((sv_559 (parse-ctx-res-val ctx)))
                (let ((sp_560 (let ((pred_562 (c99ds-ident_cont ctx env sp_558)))
                          (if pred_562
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_558)))))
                    (if sp_560
                        (let ((sv_561 (parse-ctx-res-val ctx)))
                          (let ((sp_563 (c99ds-ws ctx env sp_560)))
                              (if sp_563
                                  (let ((sv_564 (parse-ctx-res-val ctx)))
                                    (let ((sp_565 (let ((opt_567 (c99ds-identifier ctx env sp_563)))
                                              (if opt_567
                                                  opt_567
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_563)))))
                                        (if sp_565
                                            (let ((sv_566 (parse-ctx-res-val ctx)))
                                              (let ((sp_568 (c99ds-ws ctx env sp_565)))
                                                  (if sp_568
                                                      (let ((sv_569 (parse-ctx-res-val ctx)))
                                                        (let ((sp_570 (peg-ds:lit1 ctx sp_568 #\{ "{" "'{'")))
                                                            (if sp_570
                                                                (let ((sv_571 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_572 (c99ds-ws ctx env sp_570)))
                                                                      (if sp_572
                                                                          (let ((sv_573 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_574 (c99ds-enumerator_list ctx env sp_572)))
                                                                                (if sp_574
                                                                                    (let ((sv_575 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_576 (let ((opt_578 (let ((sp_579 (peg-ds:lit1 ctx sp_574 #\, "," "','")))
                                                                                                      (if sp_579
                                                                                                          (let ((sv_580 (parse-ctx-res-val ctx)))
                                                                                                            (let ((sp_581 (c99ds-ws ctx env sp_579)))
                                                                                                                (if sp_581
                                                                                                                    (let ((sv_582 (parse-ctx-res-val ctx)))
                                                                                                                      (begin
                                                                                                                          (parse-ctx-res-val-set! ctx (list sv_580 sv_582))
                                                                                                                          sp_581))
                                                                                                                    #f)))
                                                                                                          #f))))
                                                                                                (if opt_578
                                                                                                    opt_578
                                                                                                    (begin (parse-ctx-res-val-set! ctx #f) sp_574)))))
                                                                                          (if sp_576
                                                                                              (let ((sv_577 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_583 (peg-ds:lit1 ctx sp_576 #\} "}" "'}'")))
                                                                                                    (if sp_583
                                                                                                        (let ((sv_584 (parse-ctx-res-val ctx)))
                                                                                                          (let ((sp_585 (c99ds-ws ctx env sp_583)))
                                                                                                              (if sp_585
                                                                                                                  (let ((sv_586 (parse-ctx-res-val ctx)))
                                                                                                                    (begin
                                                                                                                        (parse-ctx-res-val-set! ctx (list sv_559 sv_561 sv_564 sv_566 sv_569 sv_571 sv_573 sv_575 sv_577 sv_584 sv_586))
                                                                                                                        sp_585))
                                                                                                                  #f)))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_587 (peg-ds:lit ctx pos "enum" 4 #\e "'enum'")))
          (if sp_587
              (let ((sv_588 (parse-ctx-res-val ctx)))
                (let ((sp_589 (let ((pred_591 (c99ds-ident_cont ctx env sp_587)))
                          (if pred_591
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_587)))))
                    (if sp_589
                        (let ((sv_590 (parse-ctx-res-val ctx)))
                          (let ((sp_592 (c99ds-ws ctx env sp_589)))
                              (if sp_592
                                  (let ((sv_593 (parse-ctx-res-val ctx)))
                                    (let ((sp_594 (c99ds-identifier ctx env sp_592)))
                                        (if sp_594
                                            (let ((sv_595 (parse-ctx-res-val ctx)))
                                              (let ((sp_596 (c99ds-ws ctx env sp_594)))
                                                  (if sp_596
                                                      (let ((sv_597 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_588 sv_590 sv_593 sv_595 sv_597))
                                                            sp_596))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_598
          (c99ds-decorate-rule 'enum_specifier ctx env pos rdec_598 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: enumerator_list [memo]
(define (c99ds-enumerator_list ctx env pos)
  (peg-ds:rule-memo ctx 'enumerator_list pos
    (lambda ()
      (let ((rdec_618 (let ((sp_599 (let ((np_601 (c99ds-enumerator ctx env pos)))
            (if np_601
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_601)
                #f))))
      (if sp_599
          (let ((sv_600 (parse-ctx-res-val ctx)))
            (let ((sp_602 (let ((np_604 (let rloop_605 ((rcur_606 sp_599) (racc_607 '()))
                            (let ((rnext_608 (let ((sp_609 (peg-ds:lit1 ctx rcur_606 #\, "," "','")))
                                  (if sp_609
                                      (let ((sv_610 (parse-ctx-res-val ctx)))
                                        (let ((sp_611 (c99ds-ws ctx env sp_609)))
                                            (if sp_611
                                                (let ((sv_612 (parse-ctx-res-val ctx)))
                                                  (let ((sp_613 (let ((pred_615 (peg-ds:lit1 ctx sp_611 #\} "}" "'}'")))
                                                            (if pred_615
                                                                #f
                                                                (begin (parse-ctx-res-val-set! ctx #t) sp_611)))))
                                                      (if sp_613
                                                          (let ((sv_614 (parse-ctx-res-val ctx)))
                                                            (let ((sp_616 (c99ds-enumerator ctx env sp_613)))
                                                                (if sp_616
                                                                    (let ((sv_617 (parse-ctx-res-val ctx)))
                                                                      (begin
                                                                          (parse-ctx-res-val-set! ctx (list sv_610 sv_612 sv_614 sv_617))
                                                                          sp_616))
                                                                    #f)))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_608 (> rnext_608 rcur_606))
                                  (rloop_605 rnext_608 (cons (parse-ctx-res-val ctx) racc_607))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_607)) rcur_606))))))
                      (if np_604
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_604)
                          #f))))
                (if sp_602
                    (let ((sv_603 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_600 sv_603))
                          sp_602))
                    #f)))
          #f))))
      (if rdec_618
          (c99ds-decorate-rule 'enumerator_list ctx env pos rdec_618 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: enumerator [memo]
(define (c99ds-enumerator ctx env pos)
  (peg-ds:rule-memo ctx 'enumerator pos
    (lambda ()
      (let ((rdec_630 (let ((sp_619 (c99ds-enumeration_constant ctx env pos)))
      (if sp_619
          (let ((sv_620 (parse-ctx-res-val ctx)))
            (let ((sp_621 (let ((opt_623 (let ((sp_624 (peg-ds:lit1 ctx sp_619 #\= "=" "'='")))
                            (if sp_624
                                (let ((sv_625 (parse-ctx-res-val ctx)))
                                  (let ((sp_626 (c99ds-ws ctx env sp_624)))
                                      (if sp_626
                                          (let ((sv_627 (parse-ctx-res-val ctx)))
                                            (let ((sp_628 (c99ds-constant_expr ctx env sp_626)))
                                                (if sp_628
                                                    (let ((sv_629 (parse-ctx-res-val ctx)))
                                                      (begin
                                                          (parse-ctx-res-val-set! ctx (list sv_625 sv_627 sv_629))
                                                          sp_628))
                                                    #f)))
                                          #f)))
                                #f))))
                      (if opt_623
                          opt_623
                          (begin (parse-ctx-res-val-set! ctx #f) sp_619)))))
                (if sp_621
                    (let ((sv_622 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_620 sv_622))
                          sp_621))
                    #f)))
          #f))))
      (if rdec_630
          (c99ds-decorate-rule 'enumerator ctx env pos rdec_630 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: enumeration_constant [bare]
(define (c99ds-enumeration_constant ctx env pos)
  (let ((sp_631 (c99ds-identifier ctx env pos)))
      (if sp_631
          (let ((sv_632 (parse-ctx-res-val ctx)))
            (let ((sp_633 (c99ds-ws ctx env sp_631)))
                (if sp_633
                    (let ((sv_634 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_632 sv_634))
                          sp_633))
                    #f)))
          #f)))

;;; Rule: typedef_name [bare]
(define (c99ds-typedef_name ctx env pos)
  (let ((rdec_635 (c99ds-identifier ctx env pos)))
      (if rdec_635
          (c99ds-decorate-rule 'typedef_name ctx env pos rdec_635 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: declarator [lr]
(define (c99ds-declarator ctx env pos)
  (peg-ds:rule-lr ctx 'declarator pos
    (lambda ()
      (let ((rdec_641 (let ((sp_636 (let ((opt_638 (c99ds-pointer ctx env pos)))
            (if opt_638
                opt_638
                (begin (parse-ctx-res-val-set! ctx #f) pos)))))
      (if sp_636
          (let ((sv_637 (parse-ctx-res-val ctx)))
            (let ((sp_639 (c99ds-direct_declarator ctx env sp_636)))
                (if sp_639
                    (let ((sv_640 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_637 sv_640))
                          sp_639))
                    #f)))
          #f))))
      (if rdec_641
          (c99ds-decorate-rule 'declarator ctx env pos rdec_641 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: direct_declarator [lr]
(define (c99ds-direct_declarator ctx env pos)
  (peg-ds:rule-lr ctx 'direct_declarator pos
    (lambda ()
      (let ((rdec_757 (or
      (let ((sp_642 (c99ds-direct_declarator ctx env pos)))
          (if sp_642
              (let ((sv_643 (parse-ctx-res-val ctx)))
                (let ((sp_644 (peg-ds:lit1 ctx sp_642 #\[ "[" "'['")))
                    (if sp_644
                        (let ((sv_645 (parse-ctx-res-val ctx)))
                          (let ((sp_646 (c99ds-ws ctx env sp_644)))
                              (if sp_646
                                  (let ((sv_647 (parse-ctx-res-val ctx)))
                                    (let ((sp_648 (peg-ds:lit ctx sp_646 "static" 6 #\s "'static'")))
                                        (if sp_648
                                            (let ((sv_649 (parse-ctx-res-val ctx)))
                                              (let ((sp_650 (let ((pred_652 (c99ds-ident_cont ctx env sp_648)))
                                                        (if pred_652
                                                            #f
                                                            (begin (parse-ctx-res-val-set! ctx #t) sp_648)))))
                                                  (if sp_650
                                                      (let ((sv_651 (parse-ctx-res-val ctx)))
                                                        (let ((sp_653 (c99ds-ws ctx env sp_650)))
                                                            (if sp_653
                                                                (let ((sv_654 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_655 (let ((opt_657 (c99ds-type_qualifier_list ctx env sp_653)))
                                                                            (if opt_657
                                                                                opt_657
                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_653)))))
                                                                      (if sp_655
                                                                          (let ((sv_656 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_658 (c99ds-assignment_expr ctx env sp_655)))
                                                                                (if sp_658
                                                                                    (let ((sv_659 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_660 (peg-ds:lit1 ctx sp_658 #\] "]" "']'")))
                                                                                          (if sp_660
                                                                                              (let ((sv_661 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_662 (c99ds-ws ctx env sp_660)))
                                                                                                    (if sp_662
                                                                                                        (let ((sv_663 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_643 sv_645 sv_647 sv_649 sv_651 sv_654 sv_656 sv_659 sv_661 sv_663))
                                                                                                              sp_662))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_664 (c99ds-direct_declarator ctx env pos)))
          (if sp_664
              (let ((sv_665 (parse-ctx-res-val ctx)))
                (let ((sp_666 (peg-ds:lit1 ctx sp_664 #\[ "[" "'['")))
                    (if sp_666
                        (let ((sv_667 (parse-ctx-res-val ctx)))
                          (let ((sp_668 (c99ds-ws ctx env sp_666)))
                              (if sp_668
                                  (let ((sv_669 (parse-ctx-res-val ctx)))
                                    (let ((sp_670 (c99ds-type_qualifier_list ctx env sp_668)))
                                        (if sp_670
                                            (let ((sv_671 (parse-ctx-res-val ctx)))
                                              (let ((sp_672 (peg-ds:lit ctx sp_670 "static" 6 #\s "'static'")))
                                                  (if sp_672
                                                      (let ((sv_673 (parse-ctx-res-val ctx)))
                                                        (let ((sp_674 (let ((pred_676 (c99ds-ident_cont ctx env sp_672)))
                                                                  (if pred_676
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_672)))))
                                                            (if sp_674
                                                                (let ((sv_675 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_677 (c99ds-ws ctx env sp_674)))
                                                                      (if sp_677
                                                                          (let ((sv_678 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_679 (c99ds-assignment_expr ctx env sp_677)))
                                                                                (if sp_679
                                                                                    (let ((sv_680 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_681 (peg-ds:lit1 ctx sp_679 #\] "]" "']'")))
                                                                                          (if sp_681
                                                                                              (let ((sv_682 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_683 (c99ds-ws ctx env sp_681)))
                                                                                                    (if sp_683
                                                                                                        (let ((sv_684 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_665 sv_667 sv_669 sv_671 sv_673 sv_675 sv_678 sv_680 sv_682 sv_684))
                                                                                                              sp_683))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_685 (c99ds-direct_declarator ctx env pos)))
          (if sp_685
              (let ((sv_686 (parse-ctx-res-val ctx)))
                (let ((sp_687 (peg-ds:lit1 ctx sp_685 #\[ "[" "'['")))
                    (if sp_687
                        (let ((sv_688 (parse-ctx-res-val ctx)))
                          (let ((sp_689 (c99ds-ws ctx env sp_687)))
                              (if sp_689
                                  (let ((sv_690 (parse-ctx-res-val ctx)))
                                    (let ((sp_691 (let ((opt_693 (c99ds-type_qualifier_list ctx env sp_689)))
                                              (if opt_693
                                                  opt_693
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_689)))))
                                        (if sp_691
                                            (let ((sv_692 (parse-ctx-res-val ctx)))
                                              (let ((sp_694 (peg-ds:lit1 ctx sp_691 #\* "*" "'*'")))
                                                  (if sp_694
                                                      (let ((sv_695 (parse-ctx-res-val ctx)))
                                                        (let ((sp_696 (c99ds-ws ctx env sp_694)))
                                                            (if sp_696
                                                                (let ((sv_697 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_698 (peg-ds:lit1 ctx sp_696 #\] "]" "']'")))
                                                                      (if sp_698
                                                                          (let ((sv_699 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_700 (c99ds-ws ctx env sp_698)))
                                                                                (if sp_700
                                                                                    (let ((sv_701 (parse-ctx-res-val ctx)))
                                                                                      (begin
                                                                                          (parse-ctx-res-val-set! ctx (list sv_686 sv_688 sv_690 sv_692 sv_695 sv_697 sv_699 sv_701))
                                                                                          sp_700))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_702 (c99ds-direct_declarator ctx env pos)))
          (if sp_702
              (let ((sv_703 (parse-ctx-res-val ctx)))
                (let ((sp_704 (peg-ds:lit1 ctx sp_702 #\[ "[" "'['")))
                    (if sp_704
                        (let ((sv_705 (parse-ctx-res-val ctx)))
                          (let ((sp_706 (c99ds-ws ctx env sp_704)))
                              (if sp_706
                                  (let ((sv_707 (parse-ctx-res-val ctx)))
                                    (let ((sp_708 (let ((opt_710 (c99ds-type_qualifier_list ctx env sp_706)))
                                              (if opt_710
                                                  opt_710
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_706)))))
                                        (if sp_708
                                            (let ((sv_709 (parse-ctx-res-val ctx)))
                                              (let ((sp_711 (let ((opt_713 (c99ds-assignment_expr ctx env sp_708)))
                                                        (if opt_713
                                                            opt_713
                                                            (begin (parse-ctx-res-val-set! ctx #f) sp_708)))))
                                                  (if sp_711
                                                      (let ((sv_712 (parse-ctx-res-val ctx)))
                                                        (let ((sp_714 (peg-ds:lit1 ctx sp_711 #\] "]" "']'")))
                                                            (if sp_714
                                                                (let ((sv_715 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_716 (c99ds-ws ctx env sp_714)))
                                                                      (if sp_716
                                                                          (let ((sv_717 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_703 sv_705 sv_707 sv_709 sv_712 sv_715 sv_717))
                                                                                sp_716))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_718 (c99ds-direct_declarator ctx env pos)))
          (if sp_718
              (let ((sv_719 (parse-ctx-res-val ctx)))
                (let ((sp_720 (peg-ds:lit1 ctx sp_718 #\( "(" "'('")))
                    (if sp_720
                        (let ((sv_721 (parse-ctx-res-val ctx)))
                          (let ((sp_722 (c99ds-ws ctx env sp_720)))
                              (if sp_722
                                  (let ((sv_723 (parse-ctx-res-val ctx)))
                                    (let ((sp_724 (c99ds-parameter_type_list ctx env sp_722)))
                                        (if sp_724
                                            (let ((sv_725 (parse-ctx-res-val ctx)))
                                              (let ((sp_726 (peg-ds:lit1 ctx sp_724 #\) ")" "')'")))
                                                  (if sp_726
                                                      (let ((sv_727 (parse-ctx-res-val ctx)))
                                                        (let ((sp_728 (c99ds-ws ctx env sp_726)))
                                                            (if sp_728
                                                                (let ((sv_729 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_719 sv_721 sv_723 sv_725 sv_727 sv_729))
                                                                      sp_728))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_730 (c99ds-direct_declarator ctx env pos)))
          (if sp_730
              (let ((sv_731 (parse-ctx-res-val ctx)))
                (let ((sp_732 (peg-ds:lit1 ctx sp_730 #\( "(" "'('")))
                    (if sp_732
                        (let ((sv_733 (parse-ctx-res-val ctx)))
                          (let ((sp_734 (c99ds-ws ctx env sp_732)))
                              (if sp_734
                                  (let ((sv_735 (parse-ctx-res-val ctx)))
                                    (let ((sp_736 (let ((opt_738 (c99ds-identifier_list ctx env sp_734)))
                                              (if opt_738
                                                  opt_738
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_734)))))
                                        (if sp_736
                                            (let ((sv_737 (parse-ctx-res-val ctx)))
                                              (let ((sp_739 (peg-ds:lit1 ctx sp_736 #\) ")" "')'")))
                                                  (if sp_739
                                                      (let ((sv_740 (parse-ctx-res-val ctx)))
                                                        (let ((sp_741 (c99ds-ws ctx env sp_739)))
                                                            (if sp_741
                                                                (let ((sv_742 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_731 sv_733 sv_735 sv_737 sv_740 sv_742))
                                                                      sp_741))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_743 (c99ds-identifier ctx env pos)))
          (if sp_743
              (let ((sv_744 (parse-ctx-res-val ctx)))
                (let ((sp_745 (c99ds-ws ctx env sp_743)))
                    (if sp_745
                        (let ((sv_746 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_744 sv_746))
                              sp_745))
                        #f)))
              #f))
      (let ((sp_747 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_747
              (let ((sv_748 (parse-ctx-res-val ctx)))
                (let ((sp_749 (c99ds-ws ctx env sp_747)))
                    (if sp_749
                        (let ((sv_750 (parse-ctx-res-val ctx)))
                          (let ((sp_751 (c99ds-declarator ctx env sp_749)))
                              (if sp_751
                                  (let ((sv_752 (parse-ctx-res-val ctx)))
                                    (let ((sp_753 (peg-ds:lit1 ctx sp_751 #\) ")" "')'")))
                                        (if sp_753
                                            (let ((sv_754 (parse-ctx-res-val ctx)))
                                              (let ((sp_755 (c99ds-ws ctx env sp_753)))
                                                  (if sp_755
                                                      (let ((sv_756 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_748 sv_750 sv_752 sv_754 sv_756))
                                                            sp_755))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_757
          (c99ds-decorate-rule 'direct_declarator ctx env pos rdec_757 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: pointer [memo]
(define (c99ds-pointer ctx env pos)
  (peg-ds:rule-memo ctx 'pointer pos
    (lambda ()
      (let ((rdec_778 (let ((rp1_762 (let ((sp_764 (peg-ds:lit1 ctx pos #\* "*" "'*'")))
            (if sp_764
                (let ((sv_765 (parse-ctx-res-val ctx)))
                  (let ((sp_766 (c99ds-ws ctx env sp_764)))
                      (if sp_766
                          (let ((sv_767 (parse-ctx-res-val ctx)))
                            (let ((sp_768 (let ((opt_770 (c99ds-type_qualifier_list ctx env sp_766)))
                                      (if opt_770
                                          opt_770
                                          (begin (parse-ctx-res-val-set! ctx #f) sp_766)))))
                                (if sp_768
                                    (let ((sv_769 (parse-ctx-res-val ctx)))
                                      (begin
                                          (parse-ctx-res-val-set! ctx (list sv_765 sv_767 sv_769))
                                          sp_768))
                                    #f)))
                          #f)))
                #f))))
      (if rp1_762
          (let ((rv1_763 (parse-ctx-res-val ctx)))
            (if (<= rp1_762 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_763)) rp1_762)
                (let rloop_758 ((rcur_759 rp1_762) (racc_760 (list rv1_763)))
                  (let ((rnext_761 (let ((sp_771 (peg-ds:lit1 ctx rcur_759 #\* "*" "'*'")))
                    (if sp_771
                        (let ((sv_772 (parse-ctx-res-val ctx)))
                          (let ((sp_773 (c99ds-ws ctx env sp_771)))
                              (if sp_773
                                  (let ((sv_774 (parse-ctx-res-val ctx)))
                                    (let ((sp_775 (let ((opt_777 (c99ds-type_qualifier_list ctx env sp_773)))
                                              (if opt_777
                                                  opt_777
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_773)))))
                                        (if sp_775
                                            (let ((sv_776 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_772 sv_774 sv_776))
                                                  sp_775))
                                            #f)))
                                  #f)))
                        #f))))
                    (if (and rnext_761 (> rnext_761 rcur_759))
                        (rloop_758 rnext_761 (cons (parse-ctx-res-val ctx) racc_760))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_760)) rcur_759))))))
          #f))))
      (if rdec_778
          (c99ds-decorate-rule 'pointer ctx env pos rdec_778 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: type_qualifier_list [bare]
(define (c99ds-type_qualifier_list ctx env pos)
  (let ((rp1_783 (let ((sp_785 (c99ds-type_qualifier ctx env pos)))
            (if sp_785
                (let ((sv_786 (parse-ctx-res-val ctx)))
                  (let ((sp_787 (c99ds-ws ctx env sp_785)))
                      (if sp_787
                          (let ((sv_788 (parse-ctx-res-val ctx)))
                            (begin
                                (parse-ctx-res-val-set! ctx (list sv_786 sv_788))
                                sp_787))
                          #f)))
                #f))))
      (if rp1_783
          (let ((rv1_784 (parse-ctx-res-val ctx)))
            (if (<= rp1_783 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_784)) rp1_783)
                (let rloop_779 ((rcur_780 rp1_783) (racc_781 (list rv1_784)))
                  (let ((rnext_782 (let ((sp_789 (c99ds-type_qualifier ctx env rcur_780)))
                    (if sp_789
                        (let ((sv_790 (parse-ctx-res-val ctx)))
                          (let ((sp_791 (c99ds-ws ctx env sp_789)))
                              (if sp_791
                                  (let ((sv_792 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_790 sv_792))
                                        sp_791))
                                  #f)))
                        #f))))
                    (if (and rnext_782 (> rnext_782 rcur_780))
                        (rloop_779 rnext_782 (cons (parse-ctx-res-val ctx) racc_781))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_781)) rcur_780))))))
          #f)))

;;; Rule: parameter_type_list [memo]
(define (c99ds-parameter_type_list ctx env pos)
  (peg-ds:rule-memo ctx 'parameter_type_list pos
    (lambda ()
      (let ((rdec_806 (let ((sp_793 (c99ds-parameter_list ctx env pos)))
      (if sp_793
          (let ((sv_794 (parse-ctx-res-val ctx)))
            (let ((sp_795 (let ((opt_797 (let ((sp_798 (peg-ds:lit1 ctx sp_793 #\, "," "','")))
                            (if sp_798
                                (let ((sv_799 (parse-ctx-res-val ctx)))
                                  (let ((sp_800 (c99ds-ws ctx env sp_798)))
                                      (if sp_800
                                          (let ((sv_801 (parse-ctx-res-val ctx)))
                                            (let ((sp_802 (peg-ds:lit ctx sp_800 "..." 3 #\. "'...'")))
                                                (if sp_802
                                                    (let ((sv_803 (parse-ctx-res-val ctx)))
                                                      (let ((sp_804 (c99ds-ws ctx env sp_802)))
                                                          (if sp_804
                                                              (let ((sv_805 (parse-ctx-res-val ctx)))
                                                                (begin
                                                                    (parse-ctx-res-val-set! ctx (list sv_799 sv_801 sv_803 sv_805))
                                                                    sp_804))
                                                              #f)))
                                                    #f)))
                                          #f)))
                                #f))))
                      (if opt_797
                          opt_797
                          (begin (parse-ctx-res-val-set! ctx #f) sp_793)))))
                (if sp_795
                    (let ((sv_796 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_794 sv_796))
                          sp_795))
                    #f)))
          #f))))
      (if rdec_806
          (c99ds-decorate-rule 'parameter_type_list ctx env pos rdec_806 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: parameter_list [memo]
(define (c99ds-parameter_list ctx env pos)
  (peg-ds:rule-memo ctx 'parameter_list pos
    (lambda ()
      (let ((rdec_826 (let ((sp_807 (let ((np_809 (c99ds-parameter_declaration ctx env pos)))
            (if np_809
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_809)
                #f))))
      (if sp_807
          (let ((sv_808 (parse-ctx-res-val ctx)))
            (let ((sp_810 (let ((np_812 (let rloop_813 ((rcur_814 sp_807) (racc_815 '()))
                            (let ((rnext_816 (let ((sp_817 (peg-ds:lit1 ctx rcur_814 #\, "," "','")))
                                  (if sp_817
                                      (let ((sv_818 (parse-ctx-res-val ctx)))
                                        (let ((sp_819 (c99ds-ws ctx env sp_817)))
                                            (if sp_819
                                                (let ((sv_820 (parse-ctx-res-val ctx)))
                                                  (let ((sp_821 (let ((pred_823 (peg-ds:lit ctx sp_819 "..." 3 #\. "'...'")))
                                                            (if pred_823
                                                                #f
                                                                (begin (parse-ctx-res-val-set! ctx #t) sp_819)))))
                                                      (if sp_821
                                                          (let ((sv_822 (parse-ctx-res-val ctx)))
                                                            (let ((sp_824 (c99ds-parameter_declaration ctx env sp_821)))
                                                                (if sp_824
                                                                    (let ((sv_825 (parse-ctx-res-val ctx)))
                                                                      (begin
                                                                          (parse-ctx-res-val-set! ctx (list sv_818 sv_820 sv_822 sv_825))
                                                                          sp_824))
                                                                    #f)))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_816 (> rnext_816 rcur_814))
                                  (rloop_813 rnext_816 (cons (parse-ctx-res-val ctx) racc_815))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_815)) rcur_814))))))
                      (if np_812
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_812)
                          #f))))
                (if sp_810
                    (let ((sv_811 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_808 sv_811))
                          sp_810))
                    #f)))
          #f))))
      (if rdec_826
          (c99ds-decorate-rule 'parameter_list ctx env pos rdec_826 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: parameter_declaration [memo]
(define (c99ds-parameter_declaration ctx env pos)
  (peg-ds:rule-memo ctx 'parameter_declaration pos
    (lambda ()
      (let ((rdec_848 (let ((sp_827 (c99ds-declaration_specifiers ctx env pos)))
      (if sp_827
          (let ((sv_828 (parse-ctx-res-val ctx)))
            (let ((sp_829 (let ((opt_831 (or
                            (let ((sp_832 (c99ds-declarator ctx env sp_827)))
                                (if sp_832
                                    (let ((sv_833 (parse-ctx-res-val ctx)))
                                      (let ((sp_834 (let rloop_836 ((rcur_837 sp_832) (racc_838 '()))
                                                (let ((rnext_839 (c99ds-gnu_attribute ctx env rcur_837)))
                                                  (if (and rnext_839 (> rnext_839 rcur_837))
                                                      (rloop_836 rnext_839 (cons (parse-ctx-res-val ctx) racc_838))
                                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_838)) rcur_837))))))
                                          (if sp_834
                                              (let ((sv_835 (parse-ctx-res-val ctx)))
                                                (begin
                                                    (parse-ctx-res-val-set! ctx (list sv_833 sv_835))
                                                    sp_834))
                                              #f)))
                                    #f))
                            (let ((sp_840 (c99ds-abstract_declarator ctx env sp_827)))
                                (if sp_840
                                    (let ((sv_841 (parse-ctx-res-val ctx)))
                                      (let ((sp_842 (let rloop_844 ((rcur_845 sp_840) (racc_846 '()))
                                                (let ((rnext_847 (c99ds-gnu_attribute ctx env rcur_845)))
                                                  (if (and rnext_847 (> rnext_847 rcur_845))
                                                      (rloop_844 rnext_847 (cons (parse-ctx-res-val ctx) racc_846))
                                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_846)) rcur_845))))))
                                          (if sp_842
                                              (let ((sv_843 (parse-ctx-res-val ctx)))
                                                (begin
                                                    (parse-ctx-res-val-set! ctx (list sv_841 sv_843))
                                                    sp_842))
                                              #f)))
                                    #f)))))
                      (if opt_831
                          opt_831
                          (begin (parse-ctx-res-val-set! ctx #f) sp_827)))))
                (if sp_829
                    (let ((sv_830 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_828 sv_830))
                          sp_829))
                    #f)))
          #f))))
      (if rdec_848
          (c99ds-decorate-rule 'parameter_declaration ctx env pos rdec_848 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: identifier_list [bare]
(define (c99ds-identifier_list ctx env pos)
  (let ((sp_849 (let ((np_851 (c99ds-identifier ctx env pos)))
            (if np_851
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_851)
                #f))))
      (if sp_849
          (let ((sv_850 (parse-ctx-res-val ctx)))
            (let ((sp_852 (c99ds-ws ctx env sp_849)))
                (if sp_852
                    (let ((sv_853 (parse-ctx-res-val ctx)))
                      (let ((sp_854 (let ((np_856 (let rloop_857 ((rcur_858 sp_852) (racc_859 '()))
                                      (let ((rnext_860 (let ((sp_861 (peg-ds:lit1 ctx rcur_858 #\, "," "','")))
                                            (if sp_861
                                                (let ((sv_862 (parse-ctx-res-val ctx)))
                                                  (let ((sp_863 (c99ds-ws ctx env sp_861)))
                                                      (if sp_863
                                                          (let ((sv_864 (parse-ctx-res-val ctx)))
                                                            (let ((sp_865 (c99ds-identifier ctx env sp_863)))
                                                                (if sp_865
                                                                    (let ((sv_866 (parse-ctx-res-val ctx)))
                                                                      (let ((sp_867 (c99ds-ws ctx env sp_865)))
                                                                          (if sp_867
                                                                              (let ((sv_868 (parse-ctx-res-val ctx)))
                                                                                (begin
                                                                                    (parse-ctx-res-val-set! ctx (list sv_862 sv_864 sv_866 sv_868))
                                                                                    sp_867))
                                                                              #f)))
                                                                    #f)))
                                                          #f)))
                                                #f))))
                                        (if (and rnext_860 (> rnext_860 rcur_858))
                                            (rloop_857 rnext_860 (cons (parse-ctx-res-val ctx) racc_859))
                                            (begin (parse-ctx-res-val-set! ctx (reverse racc_859)) rcur_858))))))
                                (if np_856
                                    (begin
                                      (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                                      np_856)
                                    #f))))
                          (if sp_854
                              (let ((sv_855 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_850 sv_853 sv_855))
                                    sp_854))
                              #f)))
                    #f)))
          #f)))

;;; Rule: type_name [memo]
(define (c99ds-type_name ctx env pos)
  (peg-ds:rule-memo ctx 'type_name pos
    (lambda ()
      (let ((rdec_874 (let ((sp_869 (c99ds-specifier_qualifier_list ctx env pos)))
      (if sp_869
          (let ((sv_870 (parse-ctx-res-val ctx)))
            (let ((sp_871 (let ((opt_873 (c99ds-abstract_declarator ctx env sp_869)))
                      (if opt_873
                          opt_873
                          (begin (parse-ctx-res-val-set! ctx #f) sp_869)))))
                (if sp_871
                    (let ((sv_872 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_870 sv_872))
                          sp_871))
                    #f)))
          #f))))
      (if rdec_874
          (c99ds-decorate-rule 'type_name ctx env pos rdec_874 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: abstract_declarator [lr]
(define (c99ds-abstract_declarator ctx env pos)
  (peg-ds:rule-lr ctx 'abstract_declarator pos
    (lambda ()
      (let ((rdec_880 (or
      (let ((sp_875 (c99ds-pointer ctx env pos)))
          (if sp_875
              (let ((sv_876 (parse-ctx-res-val ctx)))
                (let ((sp_877 (let ((opt_879 (c99ds-direct_abstract_declarator ctx env sp_875)))
                          (if opt_879
                              opt_879
                              (begin (parse-ctx-res-val-set! ctx #f) sp_875)))))
                    (if sp_877
                        (let ((sv_878 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_876 sv_878))
                              sp_877))
                        #f)))
              #f))
      (c99ds-direct_abstract_declarator ctx env pos))))
      (if rdec_880
          (c99ds-decorate-rule 'abstract_declarator ctx env pos rdec_880 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: direct_abstract_declarator [lr]
(define (c99ds-direct_abstract_declarator ctx env pos)
  (peg-ds:rule-lr ctx 'direct_abstract_declarator pos
    (lambda ()
      (let ((rdec_1059 (or
      (let ((sp_881 (c99ds-direct_abstract_declarator ctx env pos)))
          (if sp_881
              (let ((sv_882 (parse-ctx-res-val ctx)))
                (let ((sp_883 (peg-ds:lit1 ctx sp_881 #\[ "[" "'['")))
                    (if sp_883
                        (let ((sv_884 (parse-ctx-res-val ctx)))
                          (let ((sp_885 (c99ds-ws ctx env sp_883)))
                              (if sp_885
                                  (let ((sv_886 (parse-ctx-res-val ctx)))
                                    (let ((sp_887 (peg-ds:lit ctx sp_885 "static" 6 #\s "'static'")))
                                        (if sp_887
                                            (let ((sv_888 (parse-ctx-res-val ctx)))
                                              (let ((sp_889 (let ((pred_891 (c99ds-ident_cont ctx env sp_887)))
                                                        (if pred_891
                                                            #f
                                                            (begin (parse-ctx-res-val-set! ctx #t) sp_887)))))
                                                  (if sp_889
                                                      (let ((sv_890 (parse-ctx-res-val ctx)))
                                                        (let ((sp_892 (c99ds-ws ctx env sp_889)))
                                                            (if sp_892
                                                                (let ((sv_893 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_894 (let ((opt_896 (c99ds-type_qualifier_list ctx env sp_892)))
                                                                            (if opt_896
                                                                                opt_896
                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_892)))))
                                                                      (if sp_894
                                                                          (let ((sv_895 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_897 (c99ds-assignment_expr ctx env sp_894)))
                                                                                (if sp_897
                                                                                    (let ((sv_898 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_899 (peg-ds:lit1 ctx sp_897 #\] "]" "']'")))
                                                                                          (if sp_899
                                                                                              (let ((sv_900 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_901 (c99ds-ws ctx env sp_899)))
                                                                                                    (if sp_901
                                                                                                        (let ((sv_902 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_882 sv_884 sv_886 sv_888 sv_890 sv_893 sv_895 sv_898 sv_900 sv_902))
                                                                                                              sp_901))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_903 (c99ds-direct_abstract_declarator ctx env pos)))
          (if sp_903
              (let ((sv_904 (parse-ctx-res-val ctx)))
                (let ((sp_905 (peg-ds:lit1 ctx sp_903 #\[ "[" "'['")))
                    (if sp_905
                        (let ((sv_906 (parse-ctx-res-val ctx)))
                          (let ((sp_907 (c99ds-ws ctx env sp_905)))
                              (if sp_907
                                  (let ((sv_908 (parse-ctx-res-val ctx)))
                                    (let ((sp_909 (c99ds-type_qualifier_list ctx env sp_907)))
                                        (if sp_909
                                            (let ((sv_910 (parse-ctx-res-val ctx)))
                                              (let ((sp_911 (peg-ds:lit ctx sp_909 "static" 6 #\s "'static'")))
                                                  (if sp_911
                                                      (let ((sv_912 (parse-ctx-res-val ctx)))
                                                        (let ((sp_913 (let ((pred_915 (c99ds-ident_cont ctx env sp_911)))
                                                                  (if pred_915
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_911)))))
                                                            (if sp_913
                                                                (let ((sv_914 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_916 (c99ds-ws ctx env sp_913)))
                                                                      (if sp_916
                                                                          (let ((sv_917 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_918 (c99ds-assignment_expr ctx env sp_916)))
                                                                                (if sp_918
                                                                                    (let ((sv_919 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_920 (peg-ds:lit1 ctx sp_918 #\] "]" "']'")))
                                                                                          (if sp_920
                                                                                              (let ((sv_921 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_922 (c99ds-ws ctx env sp_920)))
                                                                                                    (if sp_922
                                                                                                        (let ((sv_923 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_904 sv_906 sv_908 sv_910 sv_912 sv_914 sv_917 sv_919 sv_921 sv_923))
                                                                                                              sp_922))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_924 (c99ds-direct_abstract_declarator ctx env pos)))
          (if sp_924
              (let ((sv_925 (parse-ctx-res-val ctx)))
                (let ((sp_926 (peg-ds:lit1 ctx sp_924 #\[ "[" "'['")))
                    (if sp_926
                        (let ((sv_927 (parse-ctx-res-val ctx)))
                          (let ((sp_928 (c99ds-ws ctx env sp_926)))
                              (if sp_928
                                  (let ((sv_929 (parse-ctx-res-val ctx)))
                                    (let ((sp_930 (let ((opt_932 (c99ds-type_qualifier_list ctx env sp_928)))
                                              (if opt_932
                                                  opt_932
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_928)))))
                                        (if sp_930
                                            (let ((sv_931 (parse-ctx-res-val ctx)))
                                              (let ((sp_933 (peg-ds:lit1 ctx sp_930 #\* "*" "'*'")))
                                                  (if sp_933
                                                      (let ((sv_934 (parse-ctx-res-val ctx)))
                                                        (let ((sp_935 (c99ds-ws ctx env sp_933)))
                                                            (if sp_935
                                                                (let ((sv_936 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_937 (peg-ds:lit1 ctx sp_935 #\] "]" "']'")))
                                                                      (if sp_937
                                                                          (let ((sv_938 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_939 (c99ds-ws ctx env sp_937)))
                                                                                (if sp_939
                                                                                    (let ((sv_940 (parse-ctx-res-val ctx)))
                                                                                      (begin
                                                                                          (parse-ctx-res-val-set! ctx (list sv_925 sv_927 sv_929 sv_931 sv_934 sv_936 sv_938 sv_940))
                                                                                          sp_939))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_941 (c99ds-direct_abstract_declarator ctx env pos)))
          (if sp_941
              (let ((sv_942 (parse-ctx-res-val ctx)))
                (let ((sp_943 (peg-ds:lit1 ctx sp_941 #\[ "[" "'['")))
                    (if sp_943
                        (let ((sv_944 (parse-ctx-res-val ctx)))
                          (let ((sp_945 (c99ds-ws ctx env sp_943)))
                              (if sp_945
                                  (let ((sv_946 (parse-ctx-res-val ctx)))
                                    (let ((sp_947 (let ((opt_949 (c99ds-type_qualifier_list ctx env sp_945)))
                                              (if opt_949
                                                  opt_949
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_945)))))
                                        (if sp_947
                                            (let ((sv_948 (parse-ctx-res-val ctx)))
                                              (let ((sp_950 (let ((opt_952 (c99ds-assignment_expr ctx env sp_947)))
                                                        (if opt_952
                                                            opt_952
                                                            (begin (parse-ctx-res-val-set! ctx #f) sp_947)))))
                                                  (if sp_950
                                                      (let ((sv_951 (parse-ctx-res-val ctx)))
                                                        (let ((sp_953 (peg-ds:lit1 ctx sp_950 #\] "]" "']'")))
                                                            (if sp_953
                                                                (let ((sv_954 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_955 (c99ds-ws ctx env sp_953)))
                                                                      (if sp_955
                                                                          (let ((sv_956 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_942 sv_944 sv_946 sv_948 sv_951 sv_954 sv_956))
                                                                                sp_955))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_957 (c99ds-direct_abstract_declarator ctx env pos)))
          (if sp_957
              (let ((sv_958 (parse-ctx-res-val ctx)))
                (let ((sp_959 (peg-ds:lit1 ctx sp_957 #\( "(" "'('")))
                    (if sp_959
                        (let ((sv_960 (parse-ctx-res-val ctx)))
                          (let ((sp_961 (c99ds-ws ctx env sp_959)))
                              (if sp_961
                                  (let ((sv_962 (parse-ctx-res-val ctx)))
                                    (let ((sp_963 (let ((opt_965 (c99ds-parameter_type_list ctx env sp_961)))
                                              (if opt_965
                                                  opt_965
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_961)))))
                                        (if sp_963
                                            (let ((sv_964 (parse-ctx-res-val ctx)))
                                              (let ((sp_966 (peg-ds:lit1 ctx sp_963 #\) ")" "')'")))
                                                  (if sp_966
                                                      (let ((sv_967 (parse-ctx-res-val ctx)))
                                                        (let ((sp_968 (c99ds-ws ctx env sp_966)))
                                                            (if sp_968
                                                                (let ((sv_969 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_958 sv_960 sv_962 sv_964 sv_967 sv_969))
                                                                      sp_968))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_970 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_970
              (let ((sv_971 (parse-ctx-res-val ctx)))
                (let ((sp_972 (c99ds-ws ctx env sp_970)))
                    (if sp_972
                        (let ((sv_973 (parse-ctx-res-val ctx)))
                          (let ((sp_974 (c99ds-abstract_declarator ctx env sp_972)))
                              (if sp_974
                                  (let ((sv_975 (parse-ctx-res-val ctx)))
                                    (let ((sp_976 (peg-ds:lit1 ctx sp_974 #\) ")" "')'")))
                                        (if sp_976
                                            (let ((sv_977 (parse-ctx-res-val ctx)))
                                              (let ((sp_978 (c99ds-ws ctx env sp_976)))
                                                  (if sp_978
                                                      (let ((sv_979 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_971 sv_973 sv_975 sv_977 sv_979))
                                                            sp_978))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_980 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_980
              (let ((sv_981 (parse-ctx-res-val ctx)))
                (let ((sp_982 (c99ds-ws ctx env sp_980)))
                    (if sp_982
                        (let ((sv_983 (parse-ctx-res-val ctx)))
                          (let ((sp_984 (peg-ds:lit ctx sp_982 "static" 6 #\s "'static'")))
                              (if sp_984
                                  (let ((sv_985 (parse-ctx-res-val ctx)))
                                    (let ((sp_986 (let ((pred_988 (c99ds-ident_cont ctx env sp_984)))
                                              (if pred_988
                                                  #f
                                                  (begin (parse-ctx-res-val-set! ctx #t) sp_984)))))
                                        (if sp_986
                                            (let ((sv_987 (parse-ctx-res-val ctx)))
                                              (let ((sp_989 (c99ds-ws ctx env sp_986)))
                                                  (if sp_989
                                                      (let ((sv_990 (parse-ctx-res-val ctx)))
                                                        (let ((sp_991 (let ((opt_993 (c99ds-type_qualifier_list ctx env sp_989)))
                                                                  (if opt_993
                                                                      opt_993
                                                                      (begin (parse-ctx-res-val-set! ctx #f) sp_989)))))
                                                            (if sp_991
                                                                (let ((sv_992 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_994 (c99ds-assignment_expr ctx env sp_991)))
                                                                      (if sp_994
                                                                          (let ((sv_995 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_996 (peg-ds:lit1 ctx sp_994 #\] "]" "']'")))
                                                                                (if sp_996
                                                                                    (let ((sv_997 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_998 (c99ds-ws ctx env sp_996)))
                                                                                          (if sp_998
                                                                                              (let ((sv_999 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_981 sv_983 sv_985 sv_987 sv_990 sv_992 sv_995 sv_997 sv_999))
                                                                                                    sp_998))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1000 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_1000
              (let ((sv_1001 (parse-ctx-res-val ctx)))
                (let ((sp_1002 (c99ds-ws ctx env sp_1000)))
                    (if sp_1002
                        (let ((sv_1003 (parse-ctx-res-val ctx)))
                          (let ((sp_1004 (c99ds-type_qualifier_list ctx env sp_1002)))
                              (if sp_1004
                                  (let ((sv_1005 (parse-ctx-res-val ctx)))
                                    (let ((sp_1006 (peg-ds:lit ctx sp_1004 "static" 6 #\s "'static'")))
                                        (if sp_1006
                                            (let ((sv_1007 (parse-ctx-res-val ctx)))
                                              (let ((sp_1008 (let ((pred_1010 (c99ds-ident_cont ctx env sp_1006)))
                                                        (if pred_1010
                                                            #f
                                                            (begin (parse-ctx-res-val-set! ctx #t) sp_1006)))))
                                                  (if sp_1008
                                                      (let ((sv_1009 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1011 (c99ds-ws ctx env sp_1008)))
                                                            (if sp_1011
                                                                (let ((sv_1012 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1013 (c99ds-assignment_expr ctx env sp_1011)))
                                                                      (if sp_1013
                                                                          (let ((sv_1014 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1015 (peg-ds:lit1 ctx sp_1013 #\] "]" "']'")))
                                                                                (if sp_1015
                                                                                    (let ((sv_1016 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1017 (c99ds-ws ctx env sp_1015)))
                                                                                          (if sp_1017
                                                                                              (let ((sv_1018 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1001 sv_1003 sv_1005 sv_1007 sv_1009 sv_1012 sv_1014 sv_1016 sv_1018))
                                                                                                    sp_1017))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1019 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_1019
              (let ((sv_1020 (parse-ctx-res-val ctx)))
                (let ((sp_1021 (c99ds-ws ctx env sp_1019)))
                    (if sp_1021
                        (let ((sv_1022 (parse-ctx-res-val ctx)))
                          (let ((sp_1023 (let ((opt_1025 (c99ds-type_qualifier_list ctx env sp_1021)))
                                    (if opt_1025
                                        opt_1025
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_1021)))))
                              (if sp_1023
                                  (let ((sv_1024 (parse-ctx-res-val ctx)))
                                    (let ((sp_1026 (peg-ds:lit1 ctx sp_1023 #\* "*" "'*'")))
                                        (if sp_1026
                                            (let ((sv_1027 (parse-ctx-res-val ctx)))
                                              (let ((sp_1028 (c99ds-ws ctx env sp_1026)))
                                                  (if sp_1028
                                                      (let ((sv_1029 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1030 (peg-ds:lit1 ctx sp_1028 #\] "]" "']'")))
                                                            (if sp_1030
                                                                (let ((sv_1031 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1032 (c99ds-ws ctx env sp_1030)))
                                                                      (if sp_1032
                                                                          (let ((sv_1033 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_1020 sv_1022 sv_1024 sv_1027 sv_1029 sv_1031 sv_1033))
                                                                                sp_1032))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1034 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_1034
              (let ((sv_1035 (parse-ctx-res-val ctx)))
                (let ((sp_1036 (c99ds-ws ctx env sp_1034)))
                    (if sp_1036
                        (let ((sv_1037 (parse-ctx-res-val ctx)))
                          (let ((sp_1038 (let ((opt_1040 (c99ds-type_qualifier_list ctx env sp_1036)))
                                    (if opt_1040
                                        opt_1040
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_1036)))))
                              (if sp_1038
                                  (let ((sv_1039 (parse-ctx-res-val ctx)))
                                    (let ((sp_1041 (let ((opt_1043 (c99ds-assignment_expr ctx env sp_1038)))
                                              (if opt_1043
                                                  opt_1043
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_1038)))))
                                        (if sp_1041
                                            (let ((sv_1042 (parse-ctx-res-val ctx)))
                                              (let ((sp_1044 (peg-ds:lit1 ctx sp_1041 #\] "]" "']'")))
                                                  (if sp_1044
                                                      (let ((sv_1045 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1046 (c99ds-ws ctx env sp_1044)))
                                                            (if sp_1046
                                                                (let ((sv_1047 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1035 sv_1037 sv_1039 sv_1042 sv_1045 sv_1047))
                                                                      sp_1046))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1048 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_1048
              (let ((sv_1049 (parse-ctx-res-val ctx)))
                (let ((sp_1050 (c99ds-ws ctx env sp_1048)))
                    (if sp_1050
                        (let ((sv_1051 (parse-ctx-res-val ctx)))
                          (let ((sp_1052 (let ((opt_1054 (c99ds-parameter_type_list ctx env sp_1050)))
                                    (if opt_1054
                                        opt_1054
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_1050)))))
                              (if sp_1052
                                  (let ((sv_1053 (parse-ctx-res-val ctx)))
                                    (let ((sp_1055 (peg-ds:lit1 ctx sp_1052 #\) ")" "')'")))
                                        (if sp_1055
                                            (let ((sv_1056 (parse-ctx-res-val ctx)))
                                              (let ((sp_1057 (c99ds-ws ctx env sp_1055)))
                                                  (if sp_1057
                                                      (let ((sv_1058 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1049 sv_1051 sv_1053 sv_1056 sv_1058))
                                                            sp_1057))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1059
          (c99ds-decorate-rule 'direct_abstract_declarator ctx env pos rdec_1059 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: initializer [memo]
(define (c99ds-initializer ctx env pos)
  (peg-ds:rule-memo ctx 'initializer pos
    (lambda ()
      (let ((rdec_1080 (or
      (let ((sp_1060 (peg-ds:lit1 ctx pos #\{ "{" "'{'")))
          (if sp_1060
              (let ((sv_1061 (parse-ctx-res-val ctx)))
                (let ((sp_1062 (c99ds-ws ctx env sp_1060)))
                    (if sp_1062
                        (let ((sv_1063 (parse-ctx-res-val ctx)))
                          (let ((sp_1064 (let ((opt_1066 (let ((sp_1067 (c99ds-initializer_list ctx env sp_1062)))
                                          (if sp_1067
                                              (let ((sv_1068 (parse-ctx-res-val ctx)))
                                                (let ((sp_1069 (let ((opt_1071 (let ((sp_1072 (peg-ds:lit1 ctx sp_1067 #\, "," "','")))
                                                                (if sp_1072
                                                                    (let ((sv_1073 (parse-ctx-res-val ctx)))
                                                                      (let ((sp_1074 (c99ds-ws ctx env sp_1072)))
                                                                          (if sp_1074
                                                                              (let ((sv_1075 (parse-ctx-res-val ctx)))
                                                                                (begin
                                                                                    (parse-ctx-res-val-set! ctx (list sv_1073 sv_1075))
                                                                                    sp_1074))
                                                                              #f)))
                                                                    #f))))
                                                          (if opt_1071
                                                              opt_1071
                                                              (begin (parse-ctx-res-val-set! ctx #f) sp_1067)))))
                                                    (if sp_1069
                                                        (let ((sv_1070 (parse-ctx-res-val ctx)))
                                                          (begin
                                                              (parse-ctx-res-val-set! ctx (list sv_1068 sv_1070))
                                                              sp_1069))
                                                        #f)))
                                              #f))))
                                    (if opt_1066
                                        opt_1066
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_1062)))))
                              (if sp_1064
                                  (let ((sv_1065 (parse-ctx-res-val ctx)))
                                    (let ((sp_1076 (peg-ds:lit1 ctx sp_1064 #\} "}" "'}'")))
                                        (if sp_1076
                                            (let ((sv_1077 (parse-ctx-res-val ctx)))
                                              (let ((sp_1078 (c99ds-ws ctx env sp_1076)))
                                                  (if sp_1078
                                                      (let ((sv_1079 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1061 sv_1063 sv_1065 sv_1077 sv_1079))
                                                            sp_1078))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (c99ds-assignment_expr ctx env pos))))
      (if rdec_1080
          (c99ds-decorate-rule 'initializer ctx env pos rdec_1080 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: initializer_list [memo]
(define (c99ds-initializer_list ctx env pos)
  (peg-ds:rule-memo ctx 'initializer_list pos
    (lambda ()
      (let ((rdec_1100 (let ((sp_1081 (let ((np_1083 (c99ds-initializer_item ctx env pos)))
            (if np_1083
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_1083)
                #f))))
      (if sp_1081
          (let ((sv_1082 (parse-ctx-res-val ctx)))
            (let ((sp_1084 (let ((np_1086 (let rloop_1087 ((rcur_1088 sp_1081) (racc_1089 '()))
                            (let ((rnext_1090 (let ((sp_1091 (peg-ds:lit1 ctx rcur_1088 #\, "," "','")))
                                  (if sp_1091
                                      (let ((sv_1092 (parse-ctx-res-val ctx)))
                                        (let ((sp_1093 (c99ds-ws ctx env sp_1091)))
                                            (if sp_1093
                                                (let ((sv_1094 (parse-ctx-res-val ctx)))
                                                  (let ((sp_1095 (let ((pred_1097 (peg-ds:lit1 ctx sp_1093 #\} "}" "'}'")))
                                                            (if pred_1097
                                                                #f
                                                                (begin (parse-ctx-res-val-set! ctx #t) sp_1093)))))
                                                      (if sp_1095
                                                          (let ((sv_1096 (parse-ctx-res-val ctx)))
                                                            (let ((sp_1098 (c99ds-initializer_item ctx env sp_1095)))
                                                                (if sp_1098
                                                                    (let ((sv_1099 (parse-ctx-res-val ctx)))
                                                                      (begin
                                                                          (parse-ctx-res-val-set! ctx (list sv_1092 sv_1094 sv_1096 sv_1099))
                                                                          sp_1098))
                                                                    #f)))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_1090 (> rnext_1090 rcur_1088))
                                  (rloop_1087 rnext_1090 (cons (parse-ctx-res-val ctx) racc_1089))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1089)) rcur_1088))))))
                      (if np_1086
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_1086)
                          #f))))
                (if sp_1084
                    (let ((sv_1085 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1082 sv_1085))
                          sp_1084))
                    #f)))
          #f))))
      (if rdec_1100
          (c99ds-decorate-rule 'initializer_list ctx env pos rdec_1100 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: initializer_item [memo]
(define (c99ds-initializer_item ctx env pos)
  (peg-ds:rule-memo ctx 'initializer_item pos
    (lambda ()
      (let ((rdec_1106 (let ((sp_1101 (let ((opt_1103 (c99ds-designation ctx env pos)))
            (if opt_1103
                opt_1103
                (begin (parse-ctx-res-val-set! ctx #f) pos)))))
      (if sp_1101
          (let ((sv_1102 (parse-ctx-res-val ctx)))
            (let ((sp_1104 (c99ds-initializer ctx env sp_1101)))
                (if sp_1104
                    (let ((sv_1105 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1102 sv_1105))
                          sp_1104))
                    #f)))
          #f))))
      (if rdec_1106
          (c99ds-decorate-rule 'initializer_item ctx env pos rdec_1106 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: designation [memo]
(define (c99ds-designation ctx env pos)
  (peg-ds:rule-memo ctx 'designation pos
    (lambda ()
      (let ((rdec_1119 (let ((sp_1107 (let ((rp1_1113 (c99ds-designator ctx env pos)))
            (if rp1_1113
                (let ((rv1_1114 (parse-ctx-res-val ctx)))
                  (if (<= rp1_1113 pos)
                      (begin (parse-ctx-res-val-set! ctx (list rv1_1114)) rp1_1113)
                      (let rloop_1109 ((rcur_1110 rp1_1113) (racc_1111 (list rv1_1114)))
                        (let ((rnext_1112 (c99ds-designator ctx env rcur_1110)))
                          (if (and rnext_1112 (> rnext_1112 rcur_1110))
                              (rloop_1109 rnext_1112 (cons (parse-ctx-res-val ctx) racc_1111))
                              (begin (parse-ctx-res-val-set! ctx (reverse racc_1111)) rcur_1110))))))
                #f))))
      (if sp_1107
          (let ((sv_1108 (parse-ctx-res-val ctx)))
            (let ((sp_1115 (peg-ds:lit1 ctx sp_1107 #\= "=" "'='")))
                (if sp_1115
                    (let ((sv_1116 (parse-ctx-res-val ctx)))
                      (let ((sp_1117 (c99ds-ws ctx env sp_1115)))
                          (if sp_1117
                              (let ((sv_1118 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1108 sv_1116 sv_1118))
                                    sp_1117))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1119
          (c99ds-decorate-rule 'designation ctx env pos rdec_1119 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: designator [memo]
(define (c99ds-designator ctx env pos)
  (peg-ds:rule-memo ctx 'designator pos
    (lambda ()
      (let ((rdec_1138 (or
      (let ((sp_1120 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_1120
              (let ((sv_1121 (parse-ctx-res-val ctx)))
                (let ((sp_1122 (c99ds-ws ctx env sp_1120)))
                    (if sp_1122
                        (let ((sv_1123 (parse-ctx-res-val ctx)))
                          (let ((sp_1124 (c99ds-constant_expr ctx env sp_1122)))
                              (if sp_1124
                                  (let ((sv_1125 (parse-ctx-res-val ctx)))
                                    (let ((sp_1126 (peg-ds:lit1 ctx sp_1124 #\] "]" "']'")))
                                        (if sp_1126
                                            (let ((sv_1127 (parse-ctx-res-val ctx)))
                                              (let ((sp_1128 (c99ds-ws ctx env sp_1126)))
                                                  (if sp_1128
                                                      (let ((sv_1129 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1121 sv_1123 sv_1125 sv_1127 sv_1129))
                                                            sp_1128))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1130 (peg-ds:lit1 ctx pos #\. "." "'.'")))
          (if sp_1130
              (let ((sv_1131 (parse-ctx-res-val ctx)))
                (let ((sp_1132 (c99ds-ws ctx env sp_1130)))
                    (if sp_1132
                        (let ((sv_1133 (parse-ctx-res-val ctx)))
                          (let ((sp_1134 (c99ds-identifier ctx env sp_1132)))
                              (if sp_1134
                                  (let ((sv_1135 (parse-ctx-res-val ctx)))
                                    (let ((sp_1136 (c99ds-ws ctx env sp_1134)))
                                        (if sp_1136
                                            (let ((sv_1137 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1131 sv_1133 sv_1135 sv_1137))
                                                  sp_1136))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1138
          (c99ds-decorate-rule 'designator ctx env pos rdec_1138 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: stmt [memo]
(define (c99ds-stmt ctx env pos)
  (peg-ds:rule-memo ctx 'stmt pos
    (lambda ()
      (or
      (c99ds-labeled_stmt ctx env pos)
      (c99ds-compound_stmt ctx env pos)
      (c99ds-selection_stmt ctx env pos)
      (c99ds-iteration_stmt ctx env pos)
      (c99ds-jump_stmt ctx env pos)
      (c99ds-asm_stmt ctx env pos)
      (c99ds-expr_stmt ctx env pos)))))

;;; Rule: asm_qual [bare]
(define (c99ds-asm_qual ctx env pos)
  (let ((sp_1139 (or
            (peg-ds:lit ctx pos "__volatile__" 12 #\_ "'__volatile__'")
            (peg-ds:lit ctx pos "__volatile" 10 #\_ "'__volatile'")
            (peg-ds:lit ctx pos "volatile" 8 #\v "'volatile'")
            (peg-ds:lit ctx pos "__inline__" 10 #\_ "'__inline__'")
            (peg-ds:lit ctx pos "__inline" 8 #\_ "'__inline'")
            (peg-ds:lit ctx pos "inline" 6 #\i "'inline'")
            (peg-ds:lit ctx pos "goto" 4 #\g "'goto'"))))
      (if sp_1139
          (let ((sv_1140 (parse-ctx-res-val ctx)))
            (let ((sp_1141 (let ((pred_1143 (c99ds-ident_cont ctx env sp_1139)))
                      (if pred_1143
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_1139)))))
                (if sp_1141
                    (let ((sv_1142 (parse-ctx-res-val ctx)))
                      (let ((sp_1144 (c99ds-ws ctx env sp_1141)))
                          (if sp_1144
                              (let ((sv_1145 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1140 sv_1142 sv_1145))
                                    sp_1144))
                              #f)))
                    #f)))
          #f)))

;;; Rule: asm_goto_labels [memo]
(define (c99ds-asm_goto_labels ctx env pos)
  (peg-ds:rule-memo ctx 'asm_goto_labels pos
    (lambda ()
      (let ((sp_1146 (peg-ds:lit1 ctx pos #\: ":" "':'")))
      (if sp_1146
          (let ((sv_1147 (parse-ctx-res-val ctx)))
            (let ((sp_1148 (c99ds-ws ctx env sp_1146)))
                (if sp_1148
                    (let ((sv_1149 (parse-ctx-res-val ctx)))
                      (let ((sp_1150 (let ((opt_1152 (let ((sp_1153 (c99ds-identifier ctx env sp_1148)))
                                      (if sp_1153
                                          (let ((sv_1154 (parse-ctx-res-val ctx)))
                                            (let ((sp_1155 (c99ds-ws ctx env sp_1153)))
                                                (if sp_1155
                                                    (let ((sv_1156 (parse-ctx-res-val ctx)))
                                                      (let ((sp_1157 (let rloop_1159 ((rcur_1160 sp_1155) (racc_1161 '()))
                                                                (let ((rnext_1162 (let ((sp_1163 (peg-ds:lit1 ctx rcur_1160 #\, "," "','")))
                                                                      (if sp_1163
                                                                          (let ((sv_1164 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1165 (c99ds-ws ctx env sp_1163)))
                                                                                (if sp_1165
                                                                                    (let ((sv_1166 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1167 (c99ds-identifier ctx env sp_1165)))
                                                                                          (if sp_1167
                                                                                              (let ((sv_1168 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1169 (c99ds-ws ctx env sp_1167)))
                                                                                                    (if sp_1169
                                                                                                        (let ((sv_1170 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_1164 sv_1166 sv_1168 sv_1170))
                                                                                                              sp_1169))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f))))
                                                                  (if (and rnext_1162 (> rnext_1162 rcur_1160))
                                                                      (rloop_1159 rnext_1162 (cons (parse-ctx-res-val ctx) racc_1161))
                                                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_1161)) rcur_1160))))))
                                                          (if sp_1157
                                                              (let ((sv_1158 (parse-ctx-res-val ctx)))
                                                                (begin
                                                                    (parse-ctx-res-val-set! ctx (list sv_1154 sv_1156 sv_1158))
                                                                    sp_1157))
                                                              #f)))
                                                    #f)))
                                          #f))))
                                (if opt_1152
                                    opt_1152
                                    (begin (parse-ctx-res-val-set! ctx #f) sp_1148)))))
                          (if sp_1150
                              (let ((sv_1151 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1147 sv_1149 sv_1151))
                                    sp_1150))
                              #f)))
                    #f)))
          #f)))))

;;; Rule: asm_stmt [memo]
(define (c99ds-asm_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'asm_stmt pos
    (lambda ()
      (let ((rdec_1210 (let ((sp_1171 (or
            (peg-ds:lit ctx pos "__asm__" 7 #\_ "'__asm__'")
            (peg-ds:lit ctx pos "__asm" 5 #\_ "'__asm'")
            (peg-ds:lit ctx pos "asm" 3 #\a "'asm'"))))
      (if sp_1171
          (let ((sv_1172 (parse-ctx-res-val ctx)))
            (let ((sp_1173 (let ((pred_1175 (c99ds-ident_cont ctx env sp_1171)))
                      (if pred_1175
                          #f
                          (begin (parse-ctx-res-val-set! ctx #t) sp_1171)))))
                (if sp_1173
                    (let ((sv_1174 (parse-ctx-res-val ctx)))
                      (let ((sp_1176 (c99ds-ws ctx env sp_1173)))
                          (if sp_1176
                              (let ((sv_1177 (parse-ctx-res-val ctx)))
                                (let ((sp_1178 (let rloop_1180 ((rcur_1181 sp_1176) (racc_1182 '()))
                                          (let ((rnext_1183 (c99ds-asm_qual ctx env rcur_1181)))
                                            (if (and rnext_1183 (> rnext_1183 rcur_1181))
                                                (rloop_1180 rnext_1183 (cons (parse-ctx-res-val ctx) racc_1182))
                                                (begin (parse-ctx-res-val-set! ctx (reverse racc_1182)) rcur_1181))))))
                                    (if sp_1178
                                        (let ((sv_1179 (parse-ctx-res-val ctx)))
                                          (let ((sp_1184 (peg-ds:lit1 ctx sp_1178 #\( "(" "'('")))
                                              (if sp_1184
                                                  (let ((sv_1185 (parse-ctx-res-val ctx)))
                                                    (let ((sp_1186 (c99ds-ws ctx env sp_1184)))
                                                        (if sp_1186
                                                            (let ((sv_1187 (parse-ctx-res-val ctx)))
                                                              (let ((sp_1188 (c99ds-asm_template ctx env sp_1186)))
                                                                  (if sp_1188
                                                                      (let ((sv_1189 (parse-ctx-res-val ctx)))
                                                                        (let ((sp_1190 (let ((opt_1192 (c99ds-asm_outputs ctx env sp_1188)))
                                                                                  (if opt_1192
                                                                                      opt_1192
                                                                                      (begin (parse-ctx-res-val-set! ctx #f) sp_1188)))))
                                                                            (if sp_1190
                                                                                (let ((sv_1191 (parse-ctx-res-val ctx)))
                                                                                  (let ((sp_1193 (let ((opt_1195 (c99ds-asm_inputs ctx env sp_1190)))
                                                                                            (if opt_1195
                                                                                                opt_1195
                                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_1190)))))
                                                                                      (if sp_1193
                                                                                          (let ((sv_1194 (parse-ctx-res-val ctx)))
                                                                                            (let ((sp_1196 (let ((opt_1198 (c99ds-asm_clobbers ctx env sp_1193)))
                                                                                                      (if opt_1198
                                                                                                          opt_1198
                                                                                                          (begin (parse-ctx-res-val-set! ctx #f) sp_1193)))))
                                                                                                (if sp_1196
                                                                                                    (let ((sv_1197 (parse-ctx-res-val ctx)))
                                                                                                      (let ((sp_1199 (let ((opt_1201 (c99ds-asm_goto_labels ctx env sp_1196)))
                                                                                                                (if opt_1201
                                                                                                                    opt_1201
                                                                                                                    (begin (parse-ctx-res-val-set! ctx #f) sp_1196)))))
                                                                                                          (if sp_1199
                                                                                                              (let ((sv_1200 (parse-ctx-res-val ctx)))
                                                                                                                (let ((sp_1202 (peg-ds:lit1 ctx sp_1199 #\) ")" "')'")))
                                                                                                                    (if sp_1202
                                                                                                                        (let ((sv_1203 (parse-ctx-res-val ctx)))
                                                                                                                          (let ((sp_1204 (c99ds-ws ctx env sp_1202)))
                                                                                                                              (if sp_1204
                                                                                                                                  (let ((sv_1205 (parse-ctx-res-val ctx)))
                                                                                                                                    (let ((sp_1206 (peg-ds:lit1 ctx sp_1204 #\; ";" "';'")))
                                                                                                                                        (if sp_1206
                                                                                                                                            (let ((sv_1207 (parse-ctx-res-val ctx)))
                                                                                                                                              (let ((sp_1208 (c99ds-ws ctx env sp_1206)))
                                                                                                                                                  (if sp_1208
                                                                                                                                                      (let ((sv_1209 (parse-ctx-res-val ctx)))
                                                                                                                                                        (begin
                                                                                                                                                            (parse-ctx-res-val-set! ctx (list sv_1172 sv_1174 sv_1177 sv_1179 sv_1185 sv_1187 sv_1189 sv_1191 sv_1194 sv_1197 sv_1200 sv_1203 sv_1205 sv_1207 sv_1209))
                                                                                                                                                            sp_1208))
                                                                                                                                                      #f)))
                                                                                                                                            #f)))
                                                                                                                                  #f)))
                                                                                                                        #f)))
                                                                                                              #f)))
                                                                                                    #f)))
                                                                                          #f)))
                                                                                #f)))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1210
          (c99ds-decorate-rule 'asm_stmt ctx env pos rdec_1210 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_template [memo]
(define (c99ds-asm_template ctx env pos)
  (peg-ds:rule-memo ctx 'asm_template pos
    (lambda ()
      (let ((rdec_1225 (let ((rp1_1215 (let ((sp_1217 (c99ds-string_literal ctx env pos)))
            (if sp_1217
                (let ((sv_1218 (parse-ctx-res-val ctx)))
                  (let ((sp_1219 (c99ds-ws ctx env sp_1217)))
                      (if sp_1219
                          (let ((sv_1220 (parse-ctx-res-val ctx)))
                            (begin
                                (parse-ctx-res-val-set! ctx (list sv_1218 sv_1220))
                                sp_1219))
                          #f)))
                #f))))
      (if rp1_1215
          (let ((rv1_1216 (parse-ctx-res-val ctx)))
            (if (<= rp1_1215 pos)
                (begin (parse-ctx-res-val-set! ctx (list rv1_1216)) rp1_1215)
                (let rloop_1211 ((rcur_1212 rp1_1215) (racc_1213 (list rv1_1216)))
                  (let ((rnext_1214 (let ((sp_1221 (c99ds-string_literal ctx env rcur_1212)))
                    (if sp_1221
                        (let ((sv_1222 (parse-ctx-res-val ctx)))
                          (let ((sp_1223 (c99ds-ws ctx env sp_1221)))
                              (if sp_1223
                                  (let ((sv_1224 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_1222 sv_1224))
                                        sp_1223))
                                  #f)))
                        #f))))
                    (if (and rnext_1214 (> rnext_1214 rcur_1212))
                        (rloop_1211 rnext_1214 (cons (parse-ctx-res-val ctx) racc_1213))
                        (begin (parse-ctx-res-val-set! ctx (reverse racc_1213)) rcur_1212))))))
          #f))))
      (if rdec_1225
          (c99ds-decorate-rule 'asm_template ctx env pos rdec_1225 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_outputs [memo]
(define (c99ds-asm_outputs ctx env pos)
  (peg-ds:rule-memo ctx 'asm_outputs pos
    (lambda ()
      (let ((rdec_1233 (let ((sp_1226 (peg-ds:lit1 ctx pos #\: ":" "':'")))
      (if sp_1226
          (let ((sv_1227 (parse-ctx-res-val ctx)))
            (let ((sp_1228 (c99ds-ws ctx env sp_1226)))
                (if sp_1228
                    (let ((sv_1229 (parse-ctx-res-val ctx)))
                      (let ((sp_1230 (let ((opt_1232 (c99ds-asm_operand_list ctx env sp_1228)))
                                (if opt_1232
                                    opt_1232
                                    (begin (parse-ctx-res-val-set! ctx #f) sp_1228)))))
                          (if sp_1230
                              (let ((sv_1231 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1227 sv_1229 sv_1231))
                                    sp_1230))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1233
          (c99ds-decorate-rule 'asm_outputs ctx env pos rdec_1233 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_inputs [memo]
(define (c99ds-asm_inputs ctx env pos)
  (peg-ds:rule-memo ctx 'asm_inputs pos
    (lambda ()
      (let ((rdec_1241 (let ((sp_1234 (peg-ds:lit1 ctx pos #\: ":" "':'")))
      (if sp_1234
          (let ((sv_1235 (parse-ctx-res-val ctx)))
            (let ((sp_1236 (c99ds-ws ctx env sp_1234)))
                (if sp_1236
                    (let ((sv_1237 (parse-ctx-res-val ctx)))
                      (let ((sp_1238 (let ((opt_1240 (c99ds-asm_operand_list ctx env sp_1236)))
                                (if opt_1240
                                    opt_1240
                                    (begin (parse-ctx-res-val-set! ctx #f) sp_1236)))))
                          (if sp_1238
                              (let ((sv_1239 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1235 sv_1237 sv_1239))
                                    sp_1238))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1241
          (c99ds-decorate-rule 'asm_inputs ctx env pos rdec_1241 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_clobbers [memo]
(define (c99ds-asm_clobbers ctx env pos)
  (peg-ds:rule-memo ctx 'asm_clobbers pos
    (lambda ()
      (let ((rdec_1249 (let ((sp_1242 (peg-ds:lit1 ctx pos #\: ":" "':'")))
      (if sp_1242
          (let ((sv_1243 (parse-ctx-res-val ctx)))
            (let ((sp_1244 (c99ds-ws ctx env sp_1242)))
                (if sp_1244
                    (let ((sv_1245 (parse-ctx-res-val ctx)))
                      (let ((sp_1246 (let ((opt_1248 (c99ds-asm_clobber_list ctx env sp_1244)))
                                (if opt_1248
                                    opt_1248
                                    (begin (parse-ctx-res-val-set! ctx #f) sp_1244)))))
                          (if sp_1246
                              (let ((sv_1247 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1243 sv_1245 sv_1247))
                                    sp_1246))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1249
          (c99ds-decorate-rule 'asm_clobbers ctx env pos rdec_1249 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_operand_list [memo]
(define (c99ds-asm_operand_list ctx env pos)
  (peg-ds:rule-memo ctx 'asm_operand_list pos
    (lambda ()
      (let ((rdec_1266 (let ((sp_1250 (let ((np_1252 (c99ds-asm_operand ctx env pos)))
            (if np_1252
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_1252)
                #f))))
      (if sp_1250
          (let ((sv_1251 (parse-ctx-res-val ctx)))
            (let ((sp_1253 (let ((np_1255 (let rloop_1256 ((rcur_1257 sp_1250) (racc_1258 '()))
                            (let ((rnext_1259 (let ((sp_1260 (peg-ds:lit1 ctx rcur_1257 #\, "," "','")))
                                  (if sp_1260
                                      (let ((sv_1261 (parse-ctx-res-val ctx)))
                                        (let ((sp_1262 (c99ds-ws ctx env sp_1260)))
                                            (if sp_1262
                                                (let ((sv_1263 (parse-ctx-res-val ctx)))
                                                  (let ((sp_1264 (c99ds-asm_operand ctx env sp_1262)))
                                                      (if sp_1264
                                                          (let ((sv_1265 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_1261 sv_1263 sv_1265))
                                                                sp_1264))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_1259 (> rnext_1259 rcur_1257))
                                  (rloop_1256 rnext_1259 (cons (parse-ctx-res-val ctx) racc_1258))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1258)) rcur_1257))))))
                      (if np_1255
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_1255)
                          #f))))
                (if sp_1253
                    (let ((sv_1254 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1251 sv_1254))
                          sp_1253))
                    #f)))
          #f))))
      (if rdec_1266
          (c99ds-decorate-rule 'asm_operand_list ctx env pos rdec_1266 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_operand [memo]
(define (c99ds-asm_operand ctx env pos)
  (peg-ds:rule-memo ctx 'asm_operand pos
    (lambda ()
      (let ((rdec_1294 (let ((sp_1267 (let ((opt_1269 (let ((sp_1270 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
                  (if sp_1270
                      (let ((sv_1271 (parse-ctx-res-val ctx)))
                        (let ((sp_1272 (c99ds-ws ctx env sp_1270)))
                            (if sp_1272
                                (let ((sv_1273 (parse-ctx-res-val ctx)))
                                  (let ((sp_1274 (c99ds-identifier ctx env sp_1272)))
                                      (if sp_1274
                                          (let ((sv_1275 (parse-ctx-res-val ctx)))
                                            (let ((sp_1276 (c99ds-ws ctx env sp_1274)))
                                                (if sp_1276
                                                    (let ((sv_1277 (parse-ctx-res-val ctx)))
                                                      (let ((sp_1278 (peg-ds:lit1 ctx sp_1276 #\] "]" "']'")))
                                                          (if sp_1278
                                                              (let ((sv_1279 (parse-ctx-res-val ctx)))
                                                                (let ((sp_1280 (c99ds-ws ctx env sp_1278)))
                                                                    (if sp_1280
                                                                        (let ((sv_1281 (parse-ctx-res-val ctx)))
                                                                          (begin
                                                                              (parse-ctx-res-val-set! ctx (list sv_1271 sv_1273 sv_1275 sv_1277 sv_1279 sv_1281))
                                                                              sp_1280))
                                                                        #f)))
                                                              #f)))
                                                    #f)))
                                          #f)))
                                #f)))
                      #f))))
            (if opt_1269
                opt_1269
                (begin (parse-ctx-res-val-set! ctx #f) pos)))))
      (if sp_1267
          (let ((sv_1268 (parse-ctx-res-val ctx)))
            (let ((sp_1282 (c99ds-asm_template ctx env sp_1267)))
                (if sp_1282
                    (let ((sv_1283 (parse-ctx-res-val ctx)))
                      (let ((sp_1284 (peg-ds:lit1 ctx sp_1282 #\( "(" "'('")))
                          (if sp_1284
                              (let ((sv_1285 (parse-ctx-res-val ctx)))
                                (let ((sp_1286 (c99ds-ws ctx env sp_1284)))
                                    (if sp_1286
                                        (let ((sv_1287 (parse-ctx-res-val ctx)))
                                          (let ((sp_1288 (c99ds-expr ctx env sp_1286)))
                                              (if sp_1288
                                                  (let ((sv_1289 (parse-ctx-res-val ctx)))
                                                    (let ((sp_1290 (peg-ds:lit1 ctx sp_1288 #\) ")" "')'")))
                                                        (if sp_1290
                                                            (let ((sv_1291 (parse-ctx-res-val ctx)))
                                                              (let ((sp_1292 (c99ds-ws ctx env sp_1290)))
                                                                  (if sp_1292
                                                                      (let ((sv_1293 (parse-ctx-res-val ctx)))
                                                                        (begin
                                                                            (parse-ctx-res-val-set! ctx (list sv_1268 sv_1283 sv_1285 sv_1287 sv_1289 sv_1291 sv_1293))
                                                                            sp_1292))
                                                                      #f)))
                                                            #f)))
                                                  #f)))
                                        #f)))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1294
          (c99ds-decorate-rule 'asm_operand ctx env pos rdec_1294 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: asm_clobber_list [memo]
(define (c99ds-asm_clobber_list ctx env pos)
  (peg-ds:rule-memo ctx 'asm_clobber_list pos
    (lambda ()
      (let ((rdec_1311 (let ((sp_1295 (let ((np_1297 (c99ds-asm_template ctx env pos)))
            (if np_1297
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_1297)
                #f))))
      (if sp_1295
          (let ((sv_1296 (parse-ctx-res-val ctx)))
            (let ((sp_1298 (let ((np_1300 (let rloop_1301 ((rcur_1302 sp_1295) (racc_1303 '()))
                            (let ((rnext_1304 (let ((sp_1305 (peg-ds:lit1 ctx rcur_1302 #\, "," "','")))
                                  (if sp_1305
                                      (let ((sv_1306 (parse-ctx-res-val ctx)))
                                        (let ((sp_1307 (c99ds-ws ctx env sp_1305)))
                                            (if sp_1307
                                                (let ((sv_1308 (parse-ctx-res-val ctx)))
                                                  (let ((sp_1309 (c99ds-asm_template ctx env sp_1307)))
                                                      (if sp_1309
                                                          (let ((sv_1310 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_1306 sv_1308 sv_1310))
                                                                sp_1309))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_1304 (> rnext_1304 rcur_1302))
                                  (rloop_1301 rnext_1304 (cons (parse-ctx-res-val ctx) racc_1303))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1303)) rcur_1302))))))
                      (if np_1300
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_1300)
                          #f))))
                (if sp_1298
                    (let ((sv_1299 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1296 sv_1299))
                          sp_1298))
                    #f)))
          #f))))
      (if rdec_1311
          (c99ds-decorate-rule 'asm_clobber_list ctx env pos rdec_1311 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: labeled_stmt [memo]
(define (c99ds-labeled_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'labeled_stmt pos
    (lambda ()
      (let ((rdec_1350 (or
      (let ((sp_1312 (peg-ds:lit ctx pos "case" 4 #\c "'case'")))
          (if sp_1312
              (let ((sv_1313 (parse-ctx-res-val ctx)))
                (let ((sp_1314 (let ((pred_1316 (c99ds-ident_cont ctx env sp_1312)))
                          (if pred_1316
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1312)))))
                    (if sp_1314
                        (let ((sv_1315 (parse-ctx-res-val ctx)))
                          (let ((sp_1317 (c99ds-ws ctx env sp_1314)))
                              (if sp_1317
                                  (let ((sv_1318 (parse-ctx-res-val ctx)))
                                    (let ((sp_1319 (c99ds-constant_expr ctx env sp_1317)))
                                        (if sp_1319
                                            (let ((sv_1320 (parse-ctx-res-val ctx)))
                                              (let ((sp_1321 (peg-ds:lit1 ctx sp_1319 #\: ":" "':'")))
                                                  (if sp_1321
                                                      (let ((sv_1322 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1323 (c99ds-ws ctx env sp_1321)))
                                                            (if sp_1323
                                                                (let ((sv_1324 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1325 (c99ds-stmt ctx env sp_1323)))
                                                                      (if sp_1325
                                                                          (let ((sv_1326 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_1313 sv_1315 sv_1318 sv_1320 sv_1322 sv_1324 sv_1326))
                                                                                sp_1325))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1327 (peg-ds:lit ctx pos "default" 7 #\d "'default'")))
          (if sp_1327
              (let ((sv_1328 (parse-ctx-res-val ctx)))
                (let ((sp_1329 (let ((pred_1331 (c99ds-ident_cont ctx env sp_1327)))
                          (if pred_1331
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1327)))))
                    (if sp_1329
                        (let ((sv_1330 (parse-ctx-res-val ctx)))
                          (let ((sp_1332 (c99ds-ws ctx env sp_1329)))
                              (if sp_1332
                                  (let ((sv_1333 (parse-ctx-res-val ctx)))
                                    (let ((sp_1334 (peg-ds:lit1 ctx sp_1332 #\: ":" "':'")))
                                        (if sp_1334
                                            (let ((sv_1335 (parse-ctx-res-val ctx)))
                                              (let ((sp_1336 (c99ds-ws ctx env sp_1334)))
                                                  (if sp_1336
                                                      (let ((sv_1337 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1338 (c99ds-stmt ctx env sp_1336)))
                                                            (if sp_1338
                                                                (let ((sv_1339 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1328 sv_1330 sv_1333 sv_1335 sv_1337 sv_1339))
                                                                      sp_1338))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1340 (c99ds-identifier ctx env pos)))
          (if sp_1340
              (let ((sv_1341 (parse-ctx-res-val ctx)))
                (let ((sp_1342 (c99ds-ws ctx env sp_1340)))
                    (if sp_1342
                        (let ((sv_1343 (parse-ctx-res-val ctx)))
                          (let ((sp_1344 (peg-ds:lit1 ctx sp_1342 #\: ":" "':'")))
                              (if sp_1344
                                  (let ((sv_1345 (parse-ctx-res-val ctx)))
                                    (let ((sp_1346 (c99ds-ws ctx env sp_1344)))
                                        (if sp_1346
                                            (let ((sv_1347 (parse-ctx-res-val ctx)))
                                              (let ((sp_1348 (c99ds-stmt ctx env sp_1346)))
                                                  (if sp_1348
                                                      (let ((sv_1349 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1341 sv_1343 sv_1345 sv_1347 sv_1349))
                                                            sp_1348))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1350
          (c99ds-decorate-rule 'labeled_stmt ctx env pos rdec_1350 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: compound_stmt [bare]
(define (c99ds-compound_stmt ctx env pos)
  (c99ds-override-compound-stmt ctx env pos))

;;; Rule: block_item [bare]
(define (c99ds-block_item ctx env pos)
  (c99ds-stmt_or_decl ctx env pos))

;;; Rule: stmt_or_decl [memo]
(define (c99ds-stmt_or_decl ctx env pos)
  (peg-ds:rule-memo ctx 'stmt_or_decl pos
    (lambda ()
      (or
      (c99ds-explicit_declaration ctx env pos)
      (c99ds-labeled_stmt ctx env pos)
      (c99ds-compound_stmt ctx env pos)
      (c99ds-selection_stmt ctx env pos)
      (c99ds-iteration_stmt ctx env pos)
      (c99ds-jump_stmt ctx env pos)
      (c99ds-asm_stmt ctx env pos)
      (c99ds-typedef_declaration ctx env pos)
      (c99ds-expr_stmt ctx env pos)))))

;;; Rule: expr_stmt [memo]
(define (c99ds-expr_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'expr_stmt pos
    (lambda ()
      (let ((rdec_1358 (let ((sp_1351 (let ((opt_1353 (c99ds-expr ctx env pos)))
            (if opt_1353
                opt_1353
                (begin (parse-ctx-res-val-set! ctx #f) pos)))))
      (if sp_1351
          (let ((sv_1352 (parse-ctx-res-val ctx)))
            (let ((sp_1354 (peg-ds:lit1 ctx sp_1351 #\; ";" "';'")))
                (if sp_1354
                    (let ((sv_1355 (parse-ctx-res-val ctx)))
                      (let ((sp_1356 (c99ds-ws ctx env sp_1354)))
                          (if sp_1356
                              (let ((sv_1357 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1352 sv_1355 sv_1357))
                                    sp_1356))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1358
          (c99ds-decorate-rule 'expr_stmt ctx env pos rdec_1358 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: selection_stmt [memo]
(define (c99ds-selection_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'selection_stmt pos
    (lambda ()
      (let ((rdec_1409 (or
      (let ((sp_1359 (peg-ds:lit ctx pos "if" 2 #\i "'if'")))
          (if sp_1359
              (let ((sv_1360 (parse-ctx-res-val ctx)))
                (let ((sp_1361 (let ((pred_1363 (c99ds-ident_cont ctx env sp_1359)))
                          (if pred_1363
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1359)))))
                    (if sp_1361
                        (let ((sv_1362 (parse-ctx-res-val ctx)))
                          (let ((sp_1364 (c99ds-ws ctx env sp_1361)))
                              (if sp_1364
                                  (let ((sv_1365 (parse-ctx-res-val ctx)))
                                    (let ((sp_1366 (peg-ds:lit1 ctx sp_1364 #\( "(" "'('")))
                                        (if sp_1366
                                            (let ((sv_1367 (parse-ctx-res-val ctx)))
                                              (let ((sp_1368 (c99ds-ws ctx env sp_1366)))
                                                  (if sp_1368
                                                      (let ((sv_1369 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1370 (c99ds-expr ctx env sp_1368)))
                                                            (if sp_1370
                                                                (let ((sv_1371 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1372 (peg-ds:lit1 ctx sp_1370 #\) ")" "')'")))
                                                                      (if sp_1372
                                                                          (let ((sv_1373 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1374 (c99ds-ws ctx env sp_1372)))
                                                                                (if sp_1374
                                                                                    (let ((sv_1375 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1376 (c99ds-stmt ctx env sp_1374)))
                                                                                          (if sp_1376
                                                                                              (let ((sv_1377 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1378 (let ((opt_1380 (let ((sp_1381 (peg-ds:lit ctx sp_1376 "else" 4 #\e "'else'")))
                                                                                                                (if sp_1381
                                                                                                                    (let ((sv_1382 (parse-ctx-res-val ctx)))
                                                                                                                      (let ((sp_1383 (let ((pred_1385 (c99ds-ident_cont ctx env sp_1381)))
                                                                                                                                (if pred_1385
                                                                                                                                    #f
                                                                                                                                    (begin (parse-ctx-res-val-set! ctx #t) sp_1381)))))
                                                                                                                          (if sp_1383
                                                                                                                              (let ((sv_1384 (parse-ctx-res-val ctx)))
                                                                                                                                (let ((sp_1386 (c99ds-ws ctx env sp_1383)))
                                                                                                                                    (if sp_1386
                                                                                                                                        (let ((sv_1387 (parse-ctx-res-val ctx)))
                                                                                                                                          (let ((sp_1388 (c99ds-stmt ctx env sp_1386)))
                                                                                                                                              (if sp_1388
                                                                                                                                                  (let ((sv_1389 (parse-ctx-res-val ctx)))
                                                                                                                                                    (begin
                                                                                                                                                        (parse-ctx-res-val-set! ctx (list sv_1382 sv_1384 sv_1387 sv_1389))
                                                                                                                                                        sp_1388))
                                                                                                                                                  #f)))
                                                                                                                                        #f)))
                                                                                                                              #f)))
                                                                                                                    #f))))
                                                                                                          (if opt_1380
                                                                                                              opt_1380
                                                                                                              (begin (parse-ctx-res-val-set! ctx #f) sp_1376)))))
                                                                                                    (if sp_1378
                                                                                                        (let ((sv_1379 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_1360 sv_1362 sv_1365 sv_1367 sv_1369 sv_1371 sv_1373 sv_1375 sv_1377 sv_1379))
                                                                                                              sp_1378))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1390 (peg-ds:lit ctx pos "switch" 6 #\s "'switch'")))
          (if sp_1390
              (let ((sv_1391 (parse-ctx-res-val ctx)))
                (let ((sp_1392 (let ((pred_1394 (c99ds-ident_cont ctx env sp_1390)))
                          (if pred_1394
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1390)))))
                    (if sp_1392
                        (let ((sv_1393 (parse-ctx-res-val ctx)))
                          (let ((sp_1395 (c99ds-ws ctx env sp_1392)))
                              (if sp_1395
                                  (let ((sv_1396 (parse-ctx-res-val ctx)))
                                    (let ((sp_1397 (peg-ds:lit1 ctx sp_1395 #\( "(" "'('")))
                                        (if sp_1397
                                            (let ((sv_1398 (parse-ctx-res-val ctx)))
                                              (let ((sp_1399 (c99ds-ws ctx env sp_1397)))
                                                  (if sp_1399
                                                      (let ((sv_1400 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1401 (c99ds-expr ctx env sp_1399)))
                                                            (if sp_1401
                                                                (let ((sv_1402 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1403 (peg-ds:lit1 ctx sp_1401 #\) ")" "')'")))
                                                                      (if sp_1403
                                                                          (let ((sv_1404 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1405 (c99ds-ws ctx env sp_1403)))
                                                                                (if sp_1405
                                                                                    (let ((sv_1406 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1407 (c99ds-stmt ctx env sp_1405)))
                                                                                          (if sp_1407
                                                                                              (let ((sv_1408 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1391 sv_1393 sv_1396 sv_1398 sv_1400 sv_1402 sv_1404 sv_1406 sv_1408))
                                                                                                    sp_1407))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1409
          (c99ds-decorate-rule 'selection_stmt ctx env pos rdec_1409 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: iteration_stmt [memo]
(define (c99ds-iteration_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'iteration_stmt pos
    (lambda ()
      (let ((rdec_1495 (or
      (let ((sp_1410 (peg-ds:lit ctx pos "while" 5 #\w "'while'")))
          (if sp_1410
              (let ((sv_1411 (parse-ctx-res-val ctx)))
                (let ((sp_1412 (let ((pred_1414 (c99ds-ident_cont ctx env sp_1410)))
                          (if pred_1414
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1410)))))
                    (if sp_1412
                        (let ((sv_1413 (parse-ctx-res-val ctx)))
                          (let ((sp_1415 (c99ds-ws ctx env sp_1412)))
                              (if sp_1415
                                  (let ((sv_1416 (parse-ctx-res-val ctx)))
                                    (let ((sp_1417 (peg-ds:lit1 ctx sp_1415 #\( "(" "'('")))
                                        (if sp_1417
                                            (let ((sv_1418 (parse-ctx-res-val ctx)))
                                              (let ((sp_1419 (c99ds-ws ctx env sp_1417)))
                                                  (if sp_1419
                                                      (let ((sv_1420 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1421 (c99ds-expr ctx env sp_1419)))
                                                            (if sp_1421
                                                                (let ((sv_1422 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1423 (peg-ds:lit1 ctx sp_1421 #\) ")" "')'")))
                                                                      (if sp_1423
                                                                          (let ((sv_1424 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1425 (c99ds-ws ctx env sp_1423)))
                                                                                (if sp_1425
                                                                                    (let ((sv_1426 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1427 (c99ds-stmt ctx env sp_1425)))
                                                                                          (if sp_1427
                                                                                              (let ((sv_1428 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1411 sv_1413 sv_1416 sv_1418 sv_1420 sv_1422 sv_1424 sv_1426 sv_1428))
                                                                                                    sp_1427))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1429 (peg-ds:lit ctx pos "do" 2 #\d "'do'")))
          (if sp_1429
              (let ((sv_1430 (parse-ctx-res-val ctx)))
                (let ((sp_1431 (let ((pred_1433 (c99ds-ident_cont ctx env sp_1429)))
                          (if pred_1433
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1429)))))
                    (if sp_1431
                        (let ((sv_1432 (parse-ctx-res-val ctx)))
                          (let ((sp_1434 (c99ds-ws ctx env sp_1431)))
                              (if sp_1434
                                  (let ((sv_1435 (parse-ctx-res-val ctx)))
                                    (let ((sp_1436 (c99ds-stmt ctx env sp_1434)))
                                        (if sp_1436
                                            (let ((sv_1437 (parse-ctx-res-val ctx)))
                                              (let ((sp_1438 (peg-ds:lit ctx sp_1436 "while" 5 #\w "'while'")))
                                                  (if sp_1438
                                                      (let ((sv_1439 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1440 (let ((pred_1442 (c99ds-ident_cont ctx env sp_1438)))
                                                                  (if pred_1442
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_1438)))))
                                                            (if sp_1440
                                                                (let ((sv_1441 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1443 (c99ds-ws ctx env sp_1440)))
                                                                      (if sp_1443
                                                                          (let ((sv_1444 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1445 (peg-ds:lit1 ctx sp_1443 #\( "(" "'('")))
                                                                                (if sp_1445
                                                                                    (let ((sv_1446 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1447 (c99ds-ws ctx env sp_1445)))
                                                                                          (if sp_1447
                                                                                              (let ((sv_1448 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1449 (c99ds-expr ctx env sp_1447)))
                                                                                                    (if sp_1449
                                                                                                        (let ((sv_1450 (parse-ctx-res-val ctx)))
                                                                                                          (let ((sp_1451 (peg-ds:lit1 ctx sp_1449 #\) ")" "')'")))
                                                                                                              (if sp_1451
                                                                                                                  (let ((sv_1452 (parse-ctx-res-val ctx)))
                                                                                                                    (let ((sp_1453 (c99ds-ws ctx env sp_1451)))
                                                                                                                        (if sp_1453
                                                                                                                            (let ((sv_1454 (parse-ctx-res-val ctx)))
                                                                                                                              (let ((sp_1455 (peg-ds:lit1 ctx sp_1453 #\; ";" "';'")))
                                                                                                                                  (if sp_1455
                                                                                                                                      (let ((sv_1456 (parse-ctx-res-val ctx)))
                                                                                                                                        (let ((sp_1457 (c99ds-ws ctx env sp_1455)))
                                                                                                                                            (if sp_1457
                                                                                                                                                (let ((sv_1458 (parse-ctx-res-val ctx)))
                                                                                                                                                  (begin
                                                                                                                                                      (parse-ctx-res-val-set! ctx (list sv_1430 sv_1432 sv_1435 sv_1437 sv_1439 sv_1441 sv_1444 sv_1446 sv_1448 sv_1450 sv_1452 sv_1454 sv_1456 sv_1458))
                                                                                                                                                      sp_1457))
                                                                                                                                                #f)))
                                                                                                                                      #f)))
                                                                                                                            #f)))
                                                                                                                  #f)))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1459 (peg-ds:lit ctx pos "for" 3 #\f "'for'")))
          (if sp_1459
              (let ((sv_1460 (parse-ctx-res-val ctx)))
                (let ((sp_1461 (let ((pred_1463 (c99ds-ident_cont ctx env sp_1459)))
                          (if pred_1463
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1459)))))
                    (if sp_1461
                        (let ((sv_1462 (parse-ctx-res-val ctx)))
                          (let ((sp_1464 (c99ds-ws ctx env sp_1461)))
                              (if sp_1464
                                  (let ((sv_1465 (parse-ctx-res-val ctx)))
                                    (let ((sp_1466 (peg-ds:lit1 ctx sp_1464 #\( "(" "'('")))
                                        (if sp_1466
                                            (let ((sv_1467 (parse-ctx-res-val ctx)))
                                              (let ((sp_1468 (c99ds-ws ctx env sp_1466)))
                                                  (if sp_1468
                                                      (let ((sv_1469 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1470 (or
                                                                  (c99ds-declaration ctx env sp_1468)
                                                                  (let ((sp_1472 (let ((opt_1474 (c99ds-expr ctx env sp_1468)))
                                                                            (if opt_1474
                                                                                opt_1474
                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_1468)))))
                                                                      (if sp_1472
                                                                          (let ((sv_1473 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1475 (peg-ds:lit1 ctx sp_1472 #\; ";" "';'")))
                                                                                (if sp_1475
                                                                                    (let ((sv_1476 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1477 (c99ds-ws ctx env sp_1475)))
                                                                                          (if sp_1477
                                                                                              (let ((sv_1478 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1473 sv_1476 sv_1478))
                                                                                                    sp_1477))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))))
                                                            (if sp_1470
                                                                (let ((sv_1471 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1479 (let ((opt_1481 (c99ds-expr ctx env sp_1470)))
                                                                            (if opt_1481
                                                                                opt_1481
                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_1470)))))
                                                                      (if sp_1479
                                                                          (let ((sv_1480 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1482 (peg-ds:lit1 ctx sp_1479 #\; ";" "';'")))
                                                                                (if sp_1482
                                                                                    (let ((sv_1483 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1484 (c99ds-ws ctx env sp_1482)))
                                                                                          (if sp_1484
                                                                                              (let ((sv_1485 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1486 (let ((opt_1488 (c99ds-expr ctx env sp_1484)))
                                                                                                          (if opt_1488
                                                                                                              opt_1488
                                                                                                              (begin (parse-ctx-res-val-set! ctx #f) sp_1484)))))
                                                                                                    (if sp_1486
                                                                                                        (let ((sv_1487 (parse-ctx-res-val ctx)))
                                                                                                          (let ((sp_1489 (peg-ds:lit1 ctx sp_1486 #\) ")" "')'")))
                                                                                                              (if sp_1489
                                                                                                                  (let ((sv_1490 (parse-ctx-res-val ctx)))
                                                                                                                    (let ((sp_1491 (c99ds-ws ctx env sp_1489)))
                                                                                                                        (if sp_1491
                                                                                                                            (let ((sv_1492 (parse-ctx-res-val ctx)))
                                                                                                                              (let ((sp_1493 (c99ds-stmt ctx env sp_1491)))
                                                                                                                                  (if sp_1493
                                                                                                                                      (let ((sv_1494 (parse-ctx-res-val ctx)))
                                                                                                                                        (begin
                                                                                                                                            (parse-ctx-res-val-set! ctx (list sv_1460 sv_1462 sv_1465 sv_1467 sv_1469 sv_1471 sv_1480 sv_1483 sv_1485 sv_1487 sv_1490 sv_1492 sv_1494))
                                                                                                                                            sp_1493))
                                                                                                                                      #f)))
                                                                                                                            #f)))
                                                                                                                  #f)))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1495
          (c99ds-decorate-rule 'iteration_stmt ctx env pos rdec_1495 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: jump_stmt [memo]
(define (c99ds-jump_stmt ctx env pos)
  (peg-ds:rule-memo ctx 'jump_stmt pos
    (lambda ()
      (let ((rdec_1547 (or
      (let ((sp_1496 (peg-ds:lit ctx pos "goto" 4 #\g "'goto'")))
          (if sp_1496
              (let ((sv_1497 (parse-ctx-res-val ctx)))
                (let ((sp_1498 (let ((pred_1500 (c99ds-ident_cont ctx env sp_1496)))
                          (if pred_1500
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1496)))))
                    (if sp_1498
                        (let ((sv_1499 (parse-ctx-res-val ctx)))
                          (let ((sp_1501 (c99ds-ws ctx env sp_1498)))
                              (if sp_1501
                                  (let ((sv_1502 (parse-ctx-res-val ctx)))
                                    (let ((sp_1503 (c99ds-identifier ctx env sp_1501)))
                                        (if sp_1503
                                            (let ((sv_1504 (parse-ctx-res-val ctx)))
                                              (let ((sp_1505 (c99ds-ws ctx env sp_1503)))
                                                  (if sp_1505
                                                      (let ((sv_1506 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1507 (peg-ds:lit1 ctx sp_1505 #\; ";" "';'")))
                                                            (if sp_1507
                                                                (let ((sv_1508 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1509 (c99ds-ws ctx env sp_1507)))
                                                                      (if sp_1509
                                                                          (let ((sv_1510 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_1497 sv_1499 sv_1502 sv_1504 sv_1506 sv_1508 sv_1510))
                                                                                sp_1509))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1511 (peg-ds:lit ctx pos "continue" 8 #\c "'continue'")))
          (if sp_1511
              (let ((sv_1512 (parse-ctx-res-val ctx)))
                (let ((sp_1513 (let ((pred_1515 (c99ds-ident_cont ctx env sp_1511)))
                          (if pred_1515
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1511)))))
                    (if sp_1513
                        (let ((sv_1514 (parse-ctx-res-val ctx)))
                          (let ((sp_1516 (c99ds-ws ctx env sp_1513)))
                              (if sp_1516
                                  (let ((sv_1517 (parse-ctx-res-val ctx)))
                                    (let ((sp_1518 (peg-ds:lit1 ctx sp_1516 #\; ";" "';'")))
                                        (if sp_1518
                                            (let ((sv_1519 (parse-ctx-res-val ctx)))
                                              (let ((sp_1520 (c99ds-ws ctx env sp_1518)))
                                                  (if sp_1520
                                                      (let ((sv_1521 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1512 sv_1514 sv_1517 sv_1519 sv_1521))
                                                            sp_1520))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1522 (peg-ds:lit ctx pos "break" 5 #\b "'break'")))
          (if sp_1522
              (let ((sv_1523 (parse-ctx-res-val ctx)))
                (let ((sp_1524 (let ((pred_1526 (c99ds-ident_cont ctx env sp_1522)))
                          (if pred_1526
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1522)))))
                    (if sp_1524
                        (let ((sv_1525 (parse-ctx-res-val ctx)))
                          (let ((sp_1527 (c99ds-ws ctx env sp_1524)))
                              (if sp_1527
                                  (let ((sv_1528 (parse-ctx-res-val ctx)))
                                    (let ((sp_1529 (peg-ds:lit1 ctx sp_1527 #\; ";" "';'")))
                                        (if sp_1529
                                            (let ((sv_1530 (parse-ctx-res-val ctx)))
                                              (let ((sp_1531 (c99ds-ws ctx env sp_1529)))
                                                  (if sp_1531
                                                      (let ((sv_1532 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1523 sv_1525 sv_1528 sv_1530 sv_1532))
                                                            sp_1531))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1533 (peg-ds:lit ctx pos "return" 6 #\r "'return'")))
          (if sp_1533
              (let ((sv_1534 (parse-ctx-res-val ctx)))
                (let ((sp_1535 (let ((pred_1537 (c99ds-ident_cont ctx env sp_1533)))
                          (if pred_1537
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1533)))))
                    (if sp_1535
                        (let ((sv_1536 (parse-ctx-res-val ctx)))
                          (let ((sp_1538 (c99ds-ws ctx env sp_1535)))
                              (if sp_1538
                                  (let ((sv_1539 (parse-ctx-res-val ctx)))
                                    (let ((sp_1540 (let ((opt_1542 (c99ds-expr ctx env sp_1538)))
                                              (if opt_1542
                                                  opt_1542
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_1538)))))
                                        (if sp_1540
                                            (let ((sv_1541 (parse-ctx-res-val ctx)))
                                              (let ((sp_1543 (peg-ds:lit1 ctx sp_1540 #\; ";" "';'")))
                                                  (if sp_1543
                                                      (let ((sv_1544 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1545 (c99ds-ws ctx env sp_1543)))
                                                            (if sp_1545
                                                                (let ((sv_1546 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1534 sv_1536 sv_1539 sv_1541 sv_1544 sv_1546))
                                                                      sp_1545))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1547
          (c99ds-decorate-rule 'jump_stmt ctx env pos rdec_1547 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: expr [memo]
(define (c99ds-expr ctx env pos)
  (peg-ds:rule-memo ctx 'expr pos
    (lambda ()
      (let ((rdec_1564 (let ((sp_1548 (let ((np_1550 (c99ds-assignment_expr ctx env pos)))
            (if np_1550
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_1550)
                #f))))
      (if sp_1548
          (let ((sv_1549 (parse-ctx-res-val ctx)))
            (let ((sp_1551 (let ((np_1553 (let rloop_1554 ((rcur_1555 sp_1548) (racc_1556 '()))
                            (let ((rnext_1557 (let ((sp_1558 (peg-ds:lit1 ctx rcur_1555 #\, "," "','")))
                                  (if sp_1558
                                      (let ((sv_1559 (parse-ctx-res-val ctx)))
                                        (let ((sp_1560 (c99ds-ws ctx env sp_1558)))
                                            (if sp_1560
                                                (let ((sv_1561 (parse-ctx-res-val ctx)))
                                                  (let ((sp_1562 (c99ds-assignment_expr ctx env sp_1560)))
                                                      (if sp_1562
                                                          (let ((sv_1563 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_1559 sv_1561 sv_1563))
                                                                sp_1562))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_1557 (> rnext_1557 rcur_1555))
                                  (rloop_1554 rnext_1557 (cons (parse-ctx-res-val ctx) racc_1556))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1556)) rcur_1555))))))
                      (if np_1553
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_1553)
                          #f))))
                (if sp_1551
                    (let ((sv_1552 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1549 sv_1552))
                          sp_1551))
                    #f)))
          #f))))
      (if rdec_1564
          (c99ds-decorate-rule 'expr ctx env pos rdec_1564 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: assignment_expr [memo]
(define (c99ds-assignment_expr ctx env pos)
  (peg-ds:rule-memo ctx 'assignment_expr pos
    (lambda ()
      (let ((rdec_1573 (or
      (let ((sp_1565 (c99ds-unary_expr ctx env pos)))
          (if sp_1565
              (let ((sv_1566 (parse-ctx-res-val ctx)))
                (let ((sp_1567 (c99ds-assignment_operator ctx env sp_1565)))
                    (if sp_1567
                        (let ((sv_1568 (parse-ctx-res-val ctx)))
                          (let ((sp_1569 (c99ds-ws ctx env sp_1567)))
                              (if sp_1569
                                  (let ((sv_1570 (parse-ctx-res-val ctx)))
                                    (let ((sp_1571 (c99ds-assignment_expr ctx env sp_1569)))
                                        (if sp_1571
                                            (let ((sv_1572 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1566 sv_1568 sv_1570 sv_1572))
                                                  sp_1571))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (c99ds-conditional_expr ctx env pos))))
      (if rdec_1573
          (c99ds-decorate-rule 'assignment_expr ctx env pos rdec_1573 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: assignment_operator [bare]
(define (c99ds-assignment_operator ctx env pos)
  (let ((rdec_1579 (or
      (let ((sp_1574 (peg-ds:lit1 ctx pos #\= "=" "'='")))
          (if sp_1574
              (let ((sv_1575 (parse-ctx-res-val ctx)))
                (let ((sp_1576 (let ((pred_1578 (peg-ds:lit1 ctx sp_1574 #\= "=" "'='")))
                          (if pred_1578
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1574)))))
                    (if sp_1576
                        (let ((sv_1577 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1575 sv_1577))
                              sp_1576))
                        #f)))
              #f))
      (peg-ds:lit ctx pos "*=" 2 #\* "'*='")
      (peg-ds:lit ctx pos "/=" 2 #\/ "'/='")
      (peg-ds:lit ctx pos "%=" 2 #\% "'%='")
      (peg-ds:lit ctx pos "+=" 2 #\+ "'+='")
      (peg-ds:lit ctx pos "-=" 2 #\- "'-='")
      (peg-ds:lit ctx pos "<<=" 3 #\< "'<<='")
      (peg-ds:lit ctx pos ">>=" 3 #\> "'>>='")
      (peg-ds:lit ctx pos "&=" 2 #\& "'&='")
      (peg-ds:lit ctx pos "^=" 2 #\^ "'^='")
      (peg-ds:lit ctx pos "|=" 2 #\| "'|='"))))
      (if rdec_1579
          (c99ds-decorate-rule 'assignment_operator ctx env pos rdec_1579 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: conditional_expr [memo]
(define (c99ds-conditional_expr ctx env pos)
  (peg-ds:rule-memo ctx 'conditional_expr pos
    (lambda ()
      (let ((rdec_1597 (let ((sp_1580 (c99ds-logical_or_expr ctx env pos)))
      (if sp_1580
          (let ((sv_1581 (parse-ctx-res-val ctx)))
            (let ((sp_1582 (let ((opt_1584 (let ((sp_1585 (peg-ds:lit1 ctx sp_1580 #\? "?" "'?'")))
                            (if sp_1585
                                (let ((sv_1586 (parse-ctx-res-val ctx)))
                                  (let ((sp_1587 (c99ds-ws ctx env sp_1585)))
                                      (if sp_1587
                                          (let ((sv_1588 (parse-ctx-res-val ctx)))
                                            (let ((sp_1589 (c99ds-expr ctx env sp_1587)))
                                                (if sp_1589
                                                    (let ((sv_1590 (parse-ctx-res-val ctx)))
                                                      (let ((sp_1591 (peg-ds:lit1 ctx sp_1589 #\: ":" "':'")))
                                                          (if sp_1591
                                                              (let ((sv_1592 (parse-ctx-res-val ctx)))
                                                                (let ((sp_1593 (c99ds-ws ctx env sp_1591)))
                                                                    (if sp_1593
                                                                        (let ((sv_1594 (parse-ctx-res-val ctx)))
                                                                          (let ((sp_1595 (c99ds-conditional_expr ctx env sp_1593)))
                                                                              (if sp_1595
                                                                                  (let ((sv_1596 (parse-ctx-res-val ctx)))
                                                                                    (begin
                                                                                        (parse-ctx-res-val-set! ctx (list sv_1586 sv_1588 sv_1590 sv_1592 sv_1594 sv_1596))
                                                                                        sp_1595))
                                                                                  #f)))
                                                                        #f)))
                                                              #f)))
                                                    #f)))
                                          #f)))
                                #f))))
                      (if opt_1584
                          opt_1584
                          (begin (parse-ctx-res-val-set! ctx #f) sp_1580)))))
                (if sp_1582
                    (let ((sv_1583 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1581 sv_1583))
                          sp_1582))
                    #f)))
          #f))))
      (if rdec_1597
          (c99ds-decorate-rule 'conditional_expr ctx env pos rdec_1597 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: constant_expr [memo]
(define (c99ds-constant_expr ctx env pos)
  (peg-ds:rule-memo ctx 'constant_expr pos
    (lambda ()
      (c99ds-conditional_expr ctx env pos))))

;;; Rule: logical_or_expr [memo]
(define (c99ds-logical_or_expr ctx env pos)
  (peg-ds:rule-memo ctx 'logical_or_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 1))))

;;; Rule: logical_and_expr [memo]
(define (c99ds-logical_and_expr ctx env pos)
  (peg-ds:rule-memo ctx 'logical_and_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 2))))

;;; Rule: inclusive_or_expr [memo]
(define (c99ds-inclusive_or_expr ctx env pos)
  (peg-ds:rule-memo ctx 'inclusive_or_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 3))))

;;; Rule: exclusive_or_expr [memo]
(define (c99ds-exclusive_or_expr ctx env pos)
  (peg-ds:rule-memo ctx 'exclusive_or_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 4))))

;;; Rule: and_expr [memo]
(define (c99ds-and_expr ctx env pos)
  (peg-ds:rule-memo ctx 'and_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 5))))

;;; Rule: equality_expr [memo]
(define (c99ds-equality_expr ctx env pos)
  (peg-ds:rule-memo ctx 'equality_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 6))))

;;; Rule: relational_expr [memo]
(define (c99ds-relational_expr ctx env pos)
  (peg-ds:rule-memo ctx 'relational_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 7))))

;;; Rule: shift_expr [memo]
(define (c99ds-shift_expr ctx env pos)
  (peg-ds:rule-memo ctx 'shift_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 8))))

;;; Rule: additive_expr [memo]
(define (c99ds-additive_expr ctx env pos)
  (peg-ds:rule-memo ctx 'additive_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 9))))

;;; Rule: multiplicative_expr [memo]
(define (c99ds-multiplicative_expr ctx env pos)
  (peg-ds:rule-memo ctx 'multiplicative_expr pos
    (lambda ()
      (c99ds-pratt-binop ctx env pos 10))))

;;; Rule: cast_expr [lr]
(define (c99ds-cast_expr ctx env pos)
  (peg-ds:rule-lr ctx 'cast_expr pos
    (lambda ()
      (let ((rdec_1613 (or
      (let ((sp_1598 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_1598
              (let ((sv_1599 (parse-ctx-res-val ctx)))
                (let ((sp_1600 (c99ds-ws ctx env sp_1598)))
                    (if sp_1600
                        (let ((sv_1601 (parse-ctx-res-val ctx)))
                          (let ((sp_1602 (c99ds-type_name ctx env sp_1600)))
                              (if sp_1602
                                  (let ((sv_1603 (parse-ctx-res-val ctx)))
                                    (let ((sp_1604 (peg-ds:lit1 ctx sp_1602 #\) ")" "')'")))
                                        (if sp_1604
                                            (let ((sv_1605 (parse-ctx-res-val ctx)))
                                              (let ((sp_1606 (c99ds-ws ctx env sp_1604)))
                                                  (if sp_1606
                                                      (let ((sv_1607 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1608 (let ((pred_1610 (peg-ds:lit1 ctx sp_1606 #\{ "{" "'{'")))
                                                                  (if pred_1610
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_1606)))))
                                                            (if sp_1608
                                                                (let ((sv_1609 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1611 (c99ds-cast_expr ctx env sp_1608)))
                                                                      (if sp_1611
                                                                          (let ((sv_1612 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_1599 sv_1601 sv_1603 sv_1605 sv_1607 sv_1609 sv_1612))
                                                                                sp_1611))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (c99ds-unary_expr ctx env pos))))
      (if rdec_1613
          (c99ds-decorate-rule 'cast_expr ctx env pos rdec_1613 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: unary_expr [lr]
(define (c99ds-unary_expr ctx env pos)
  (peg-ds:rule-lr ctx 'unary_expr pos
    (lambda ()
      (let ((rdec_1716 (or
      (let ((sp_1614 (or
                (peg-ds:lit ctx pos "++" 2 #\+ "'++'")
                (peg-ds:lit ctx pos "--" 2 #\- "'--'"))))
          (if sp_1614
              (let ((sv_1615 (parse-ctx-res-val ctx)))
                (let ((sp_1616 (c99ds-ws ctx env sp_1614)))
                    (if sp_1616
                        (let ((sv_1617 (parse-ctx-res-val ctx)))
                          (let ((sp_1618 (c99ds-unary_expr ctx env sp_1616)))
                              (if sp_1618
                                  (let ((sv_1619 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_1615 sv_1617 sv_1619))
                                        sp_1618))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1620 (c99ds-unary_operator ctx env pos)))
          (if sp_1620
              (let ((sv_1621 (parse-ctx-res-val ctx)))
                (let ((sp_1622 (c99ds-ws ctx env sp_1620)))
                    (if sp_1622
                        (let ((sv_1623 (parse-ctx-res-val ctx)))
                          (let ((sp_1624 (c99ds-cast_expr ctx env sp_1622)))
                              (if sp_1624
                                  (let ((sv_1625 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_1621 sv_1623 sv_1625))
                                        sp_1624))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1626 (peg-ds:lit ctx pos "sizeof" 6 #\s "'sizeof'")))
          (if sp_1626
              (let ((sv_1627 (parse-ctx-res-val ctx)))
                (let ((sp_1628 (let ((pred_1630 (c99ds-ident_cont ctx env sp_1626)))
                          (if pred_1630
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1626)))))
                    (if sp_1628
                        (let ((sv_1629 (parse-ctx-res-val ctx)))
                          (let ((sp_1631 (c99ds-ws ctx env sp_1628)))
                              (if sp_1631
                                  (let ((sv_1632 (parse-ctx-res-val ctx)))
                                    (let ((sp_1633 (peg-ds:lit1 ctx sp_1631 #\( "(" "'('")))
                                        (if sp_1633
                                            (let ((sv_1634 (parse-ctx-res-val ctx)))
                                              (let ((sp_1635 (c99ds-ws ctx env sp_1633)))
                                                  (if sp_1635
                                                      (let ((sv_1636 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1637 (c99ds-type_name ctx env sp_1635)))
                                                            (if sp_1637
                                                                (let ((sv_1638 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1639 (peg-ds:lit1 ctx sp_1637 #\) ")" "')'")))
                                                                      (if sp_1639
                                                                          (let ((sv_1640 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1641 (c99ds-ws ctx env sp_1639)))
                                                                                (if sp_1641
                                                                                    (let ((sv_1642 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1643 (let ((pred_1645 (peg-ds:lit1 ctx sp_1641 #\{ "{" "'{'")))
                                                                                                (if pred_1645
                                                                                                    #f
                                                                                                    (begin (parse-ctx-res-val-set! ctx #t) sp_1641)))))
                                                                                          (if sp_1643
                                                                                              (let ((sv_1644 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1627 sv_1629 sv_1632 sv_1634 sv_1636 sv_1638 sv_1640 sv_1642 sv_1644))
                                                                                                    sp_1643))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1646 (peg-ds:lit ctx pos "sizeof" 6 #\s "'sizeof'")))
          (if sp_1646
              (let ((sv_1647 (parse-ctx-res-val ctx)))
                (let ((sp_1648 (let ((pred_1650 (c99ds-ident_cont ctx env sp_1646)))
                          (if pred_1650
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1646)))))
                    (if sp_1648
                        (let ((sv_1649 (parse-ctx-res-val ctx)))
                          (let ((sp_1651 (c99ds-ws ctx env sp_1648)))
                              (if sp_1651
                                  (let ((sv_1652 (parse-ctx-res-val ctx)))
                                    (let ((sp_1653 (c99ds-unary_expr ctx env sp_1651)))
                                        (if sp_1653
                                            (let ((sv_1654 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1647 sv_1649 sv_1652 sv_1654))
                                                  sp_1653))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1655 (or
                (peg-ds:lit ctx pos "_Alignof" 8 #\_ "'_Alignof'")
                (peg-ds:lit ctx pos "__alignof__" 11 #\_ "'__alignof__'")
                (peg-ds:lit ctx pos "__alignof" 9 #\_ "'__alignof'"))))
          (if sp_1655
              (let ((sv_1656 (parse-ctx-res-val ctx)))
                (let ((sp_1657 (let ((pred_1659 (c99ds-ident_cont ctx env sp_1655)))
                          (if pred_1659
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1655)))))
                    (if sp_1657
                        (let ((sv_1658 (parse-ctx-res-val ctx)))
                          (let ((sp_1660 (c99ds-ws ctx env sp_1657)))
                              (if sp_1660
                                  (let ((sv_1661 (parse-ctx-res-val ctx)))
                                    (let ((sp_1662 (peg-ds:lit1 ctx sp_1660 #\( "(" "'('")))
                                        (if sp_1662
                                            (let ((sv_1663 (parse-ctx-res-val ctx)))
                                              (let ((sp_1664 (c99ds-ws ctx env sp_1662)))
                                                  (if sp_1664
                                                      (let ((sv_1665 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1666 (c99ds-type_name ctx env sp_1664)))
                                                            (if sp_1666
                                                                (let ((sv_1667 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1668 (peg-ds:lit1 ctx sp_1666 #\) ")" "')'")))
                                                                      (if sp_1668
                                                                          (let ((sv_1669 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1670 (c99ds-ws ctx env sp_1668)))
                                                                                (if sp_1670
                                                                                    (let ((sv_1671 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1672 (let ((pred_1674 (peg-ds:lit1 ctx sp_1670 #\{ "{" "'{'")))
                                                                                                (if pred_1674
                                                                                                    #f
                                                                                                    (begin (parse-ctx-res-val-set! ctx #t) sp_1670)))))
                                                                                          (if sp_1672
                                                                                              (let ((sv_1673 (parse-ctx-res-val ctx)))
                                                                                                (begin
                                                                                                    (parse-ctx-res-val-set! ctx (list sv_1656 sv_1658 sv_1661 sv_1663 sv_1665 sv_1667 sv_1669 sv_1671 sv_1673))
                                                                                                    sp_1672))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1675 (or
                (peg-ds:lit ctx pos "_Alignof" 8 #\_ "'_Alignof'")
                (peg-ds:lit ctx pos "__alignof__" 11 #\_ "'__alignof__'")
                (peg-ds:lit ctx pos "__alignof" 9 #\_ "'__alignof'"))))
          (if sp_1675
              (let ((sv_1676 (parse-ctx-res-val ctx)))
                (let ((sp_1677 (let ((pred_1679 (c99ds-ident_cont ctx env sp_1675)))
                          (if pred_1679
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1675)))))
                    (if sp_1677
                        (let ((sv_1678 (parse-ctx-res-val ctx)))
                          (let ((sp_1680 (c99ds-ws ctx env sp_1677)))
                              (if sp_1680
                                  (let ((sv_1681 (parse-ctx-res-val ctx)))
                                    (let ((sp_1682 (c99ds-unary_expr ctx env sp_1680)))
                                        (if sp_1682
                                            (let ((sv_1683 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1676 sv_1678 sv_1681 sv_1683))
                                                  sp_1682))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1684 (peg-ds:lit ctx pos "__builtin_offsetof" 18 #\_ "'__builtin_offsetof'")))
          (if sp_1684
              (let ((sv_1685 (parse-ctx-res-val ctx)))
                (let ((sp_1686 (let ((pred_1688 (c99ds-ident_cont ctx env sp_1684)))
                          (if pred_1688
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1684)))))
                    (if sp_1686
                        (let ((sv_1687 (parse-ctx-res-val ctx)))
                          (let ((sp_1689 (c99ds-ws ctx env sp_1686)))
                              (if sp_1689
                                  (let ((sv_1690 (parse-ctx-res-val ctx)))
                                    (let ((sp_1691 (peg-ds:lit1 ctx sp_1689 #\( "(" "'('")))
                                        (if sp_1691
                                            (let ((sv_1692 (parse-ctx-res-val ctx)))
                                              (let ((sp_1693 (c99ds-ws ctx env sp_1691)))
                                                  (if sp_1693
                                                      (let ((sv_1694 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1695 (c99ds-type_name ctx env sp_1693)))
                                                            (if sp_1695
                                                                (let ((sv_1696 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1697 (peg-ds:lit1 ctx sp_1695 #\, "," "','")))
                                                                      (if sp_1697
                                                                          (let ((sv_1698 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1699 (c99ds-ws ctx env sp_1697)))
                                                                                (if sp_1699
                                                                                    (let ((sv_1700 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1701 (c99ds-offsetof_member_designator ctx env sp_1699)))
                                                                                          (if sp_1701
                                                                                              (let ((sv_1702 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1703 (peg-ds:lit1 ctx sp_1701 #\) ")" "')'")))
                                                                                                    (if sp_1703
                                                                                                        (let ((sv_1704 (parse-ctx-res-val ctx)))
                                                                                                          (let ((sp_1705 (c99ds-ws ctx env sp_1703)))
                                                                                                              (if sp_1705
                                                                                                                  (let ((sv_1706 (parse-ctx-res-val ctx)))
                                                                                                                    (begin
                                                                                                                        (parse-ctx-res-val-set! ctx (list sv_1685 sv_1687 sv_1690 sv_1692 sv_1694 sv_1696 sv_1698 sv_1700 sv_1702 sv_1704 sv_1706))
                                                                                                                        sp_1705))
                                                                                                                  #f)))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1707 (peg-ds:lit ctx pos "__extension__" 13 #\_ "'__extension__'")))
          (if sp_1707
              (let ((sv_1708 (parse-ctx-res-val ctx)))
                (let ((sp_1709 (let ((pred_1711 (c99ds-ident_cont ctx env sp_1707)))
                          (if pred_1711
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1707)))))
                    (if sp_1709
                        (let ((sv_1710 (parse-ctx-res-val ctx)))
                          (let ((sp_1712 (c99ds-ws ctx env sp_1709)))
                              (if sp_1712
                                  (let ((sv_1713 (parse-ctx-res-val ctx)))
                                    (let ((sp_1714 (c99ds-cast_expr ctx env sp_1712)))
                                        (if sp_1714
                                            (let ((sv_1715 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1708 sv_1710 sv_1713 sv_1715))
                                                  sp_1714))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (c99ds-postfix_expr ctx env pos))))
      (if rdec_1716
          (c99ds-decorate-rule 'unary_expr ctx env pos rdec_1716 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: offsetof_member_designator [memo]
(define (c99ds-offsetof_member_designator ctx env pos)
  (peg-ds:rule-memo ctx 'offsetof_member_designator pos
    (lambda ()
      (let ((rdec_1727 (let ((sp_1717 (c99ds-identifier ctx env pos)))
      (if sp_1717
          (let ((sv_1718 (parse-ctx-res-val ctx)))
            (let ((sp_1719 (c99ds-ws ctx env sp_1717)))
                (if sp_1719
                    (let ((sv_1720 (parse-ctx-res-val ctx)))
                      (let ((sp_1721 (let rloop_1723 ((rcur_1724 sp_1719) (racc_1725 '()))
                                (let ((rnext_1726 (c99ds-offsetof_designator_suffix ctx env rcur_1724)))
                                  (if (and rnext_1726 (> rnext_1726 rcur_1724))
                                      (rloop_1723 rnext_1726 (cons (parse-ctx-res-val ctx) racc_1725))
                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_1725)) rcur_1724))))))
                          (if sp_1721
                              (let ((sv_1722 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1718 sv_1720 sv_1722))
                                    sp_1721))
                              #f)))
                    #f)))
          #f))))
      (if rdec_1727
          (c99ds-decorate-rule 'offsetof_member_designator ctx env pos rdec_1727 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: offsetof_designator_suffix [bare]
(define (c99ds-offsetof_designator_suffix ctx env pos)
  (let ((rdec_1746 (or
      (let ((sp_1728 (peg-ds:lit1 ctx pos #\. "." "'.'")))
          (if sp_1728
              (let ((sv_1729 (parse-ctx-res-val ctx)))
                (let ((sp_1730 (c99ds-ws ctx env sp_1728)))
                    (if sp_1730
                        (let ((sv_1731 (parse-ctx-res-val ctx)))
                          (let ((sp_1732 (c99ds-identifier ctx env sp_1730)))
                              (if sp_1732
                                  (let ((sv_1733 (parse-ctx-res-val ctx)))
                                    (let ((sp_1734 (c99ds-ws ctx env sp_1732)))
                                        (if sp_1734
                                            (let ((sv_1735 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_1729 sv_1731 sv_1733 sv_1735))
                                                  sp_1734))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1736 (peg-ds:lit1 ctx pos #\[ "[" "'['")))
          (if sp_1736
              (let ((sv_1737 (parse-ctx-res-val ctx)))
                (let ((sp_1738 (c99ds-ws ctx env sp_1736)))
                    (if sp_1738
                        (let ((sv_1739 (parse-ctx-res-val ctx)))
                          (let ((sp_1740 (c99ds-constant_expr ctx env sp_1738)))
                              (if sp_1740
                                  (let ((sv_1741 (parse-ctx-res-val ctx)))
                                    (let ((sp_1742 (peg-ds:lit1 ctx sp_1740 #\] "]" "']'")))
                                        (if sp_1742
                                            (let ((sv_1743 (parse-ctx-res-val ctx)))
                                              (let ((sp_1744 (c99ds-ws ctx env sp_1742)))
                                                  (if sp_1744
                                                      (let ((sv_1745 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1737 sv_1739 sv_1741 sv_1743 sv_1745))
                                                            sp_1744))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1746
          (c99ds-decorate-rule 'offsetof_designator_suffix ctx env pos rdec_1746 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: unary_operator [bare]
(define (c99ds-unary_operator ctx env pos)
  (let ((rdec_1767 (or
      (let ((sp_1747 (peg-ds:lit1 ctx pos #\& "&" "'&'")))
          (if sp_1747
              (let ((sv_1748 (parse-ctx-res-val ctx)))
                (let ((sp_1749 (let ((pred_1751 (peg-ds:lit1 ctx sp_1747 #\& "&" "'&'")))
                          (if pred_1751
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1747)))))
                    (if sp_1749
                        (let ((sv_1750 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1748 sv_1750))
                              sp_1749))
                        #f)))
              #f))
      (peg-ds:lit1 ctx pos #\* "*" "'*'")
      (let ((sp_1752 (peg-ds:lit1 ctx pos #\+ "+" "'+'")))
          (if sp_1752
              (let ((sv_1753 (parse-ctx-res-val ctx)))
                (let ((sp_1754 (let ((pred_1756 (peg-ds:lit1 ctx sp_1752 #\+ "+" "'+'")))
                          (if pred_1756
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1752)))))
                    (if sp_1754
                        (let ((sv_1755 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1753 sv_1755))
                              sp_1754))
                        #f)))
              #f))
      (let ((sp_1757 (peg-ds:lit1 ctx pos #\- "-" "'-'")))
          (if sp_1757
              (let ((sv_1758 (parse-ctx-res-val ctx)))
                (let ((sp_1759 (let ((pred_1761 (peg-ds:lit1 ctx sp_1757 #\- "-" "'-'")))
                          (if pred_1761
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1757)))))
                    (if sp_1759
                        (let ((sv_1760 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1758 sv_1760))
                              sp_1759))
                        #f)))
              #f))
      (peg-ds:lit1 ctx pos #\~ "~" "'~'")
      (let ((sp_1762 (peg-ds:lit1 ctx pos #\! "!" "'!'")))
          (if sp_1762
              (let ((sv_1763 (parse-ctx-res-val ctx)))
                (let ((sp_1764 (let ((pred_1766 (peg-ds:lit1 ctx sp_1762 #\= "=" "'='")))
                          (if pred_1766
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1762)))))
                    (if sp_1764
                        (let ((sv_1765 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1763 sv_1765))
                              sp_1764))
                        #f)))
              #f)))))
      (if rdec_1767
          (c99ds-decorate-rule 'unary_operator ctx env pos rdec_1767 (parse-ctx-res-val ctx))
          #f)))

;;; Rule: postfix_expr [lr]
(define (c99ds-postfix_expr ctx env pos)
  (peg-ds:rule-lr ctx 'postfix_expr pos
    (lambda ()
      (let ((rdec_1849 (or
      (let ((sp_1768 (c99ds-postfix_expr ctx env pos)))
          (if sp_1768
              (let ((sv_1769 (parse-ctx-res-val ctx)))
                (let ((sp_1770 (peg-ds:lit1 ctx sp_1768 #\[ "[" "'['")))
                    (if sp_1770
                        (let ((sv_1771 (parse-ctx-res-val ctx)))
                          (let ((sp_1772 (c99ds-ws ctx env sp_1770)))
                              (if sp_1772
                                  (let ((sv_1773 (parse-ctx-res-val ctx)))
                                    (let ((sp_1774 (c99ds-expr ctx env sp_1772)))
                                        (if sp_1774
                                            (let ((sv_1775 (parse-ctx-res-val ctx)))
                                              (let ((sp_1776 (peg-ds:lit1 ctx sp_1774 #\] "]" "']'")))
                                                  (if sp_1776
                                                      (let ((sv_1777 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1778 (c99ds-ws ctx env sp_1776)))
                                                            (if sp_1778
                                                                (let ((sv_1779 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1769 sv_1771 sv_1773 sv_1775 sv_1777 sv_1779))
                                                                      sp_1778))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1780 (c99ds-postfix_expr ctx env pos)))
          (if sp_1780
              (let ((sv_1781 (parse-ctx-res-val ctx)))
                (let ((sp_1782 (peg-ds:lit1 ctx sp_1780 #\( "(" "'('")))
                    (if sp_1782
                        (let ((sv_1783 (parse-ctx-res-val ctx)))
                          (let ((sp_1784 (c99ds-ws ctx env sp_1782)))
                              (if sp_1784
                                  (let ((sv_1785 (parse-ctx-res-val ctx)))
                                    (let ((sp_1786 (let ((opt_1788 (c99ds-argument_expr_list ctx env sp_1784)))
                                              (if opt_1788
                                                  opt_1788
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_1784)))))
                                        (if sp_1786
                                            (let ((sv_1787 (parse-ctx-res-val ctx)))
                                              (let ((sp_1789 (peg-ds:lit1 ctx sp_1786 #\) ")" "')'")))
                                                  (if sp_1789
                                                      (let ((sv_1790 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1791 (c99ds-ws ctx env sp_1789)))
                                                            (if sp_1791
                                                                (let ((sv_1792 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1781 sv_1783 sv_1785 sv_1787 sv_1790 sv_1792))
                                                                      sp_1791))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1793 (c99ds-postfix_expr ctx env pos)))
          (if sp_1793
              (let ((sv_1794 (parse-ctx-res-val ctx)))
                (let ((sp_1795 (peg-ds:lit1 ctx sp_1793 #\. "." "'.'")))
                    (if sp_1795
                        (let ((sv_1796 (parse-ctx-res-val ctx)))
                          (let ((sp_1797 (c99ds-ws ctx env sp_1795)))
                              (if sp_1797
                                  (let ((sv_1798 (parse-ctx-res-val ctx)))
                                    (let ((sp_1799 (c99ds-identifier ctx env sp_1797)))
                                        (if sp_1799
                                            (let ((sv_1800 (parse-ctx-res-val ctx)))
                                              (let ((sp_1801 (c99ds-ws ctx env sp_1799)))
                                                  (if sp_1801
                                                      (let ((sv_1802 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1794 sv_1796 sv_1798 sv_1800 sv_1802))
                                                            sp_1801))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1803 (c99ds-postfix_expr ctx env pos)))
          (if sp_1803
              (let ((sv_1804 (parse-ctx-res-val ctx)))
                (let ((sp_1805 (peg-ds:lit ctx sp_1803 "->" 2 #\- "'->'")))
                    (if sp_1805
                        (let ((sv_1806 (parse-ctx-res-val ctx)))
                          (let ((sp_1807 (c99ds-ws ctx env sp_1805)))
                              (if sp_1807
                                  (let ((sv_1808 (parse-ctx-res-val ctx)))
                                    (let ((sp_1809 (c99ds-identifier ctx env sp_1807)))
                                        (if sp_1809
                                            (let ((sv_1810 (parse-ctx-res-val ctx)))
                                              (let ((sp_1811 (c99ds-ws ctx env sp_1809)))
                                                  (if sp_1811
                                                      (let ((sv_1812 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1804 sv_1806 sv_1808 sv_1810 sv_1812))
                                                            sp_1811))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1813 (c99ds-postfix_expr ctx env pos)))
          (if sp_1813
              (let ((sv_1814 (parse-ctx-res-val ctx)))
                (let ((sp_1815 (or
                          (peg-ds:lit ctx sp_1813 "++" 2 #\+ "'++'")
                          (peg-ds:lit ctx sp_1813 "--" 2 #\- "'--'"))))
                    (if sp_1815
                        (let ((sv_1816 (parse-ctx-res-val ctx)))
                          (let ((sp_1817 (c99ds-ws ctx env sp_1815)))
                              (if sp_1817
                                  (let ((sv_1818 (parse-ctx-res-val ctx)))
                                    (begin
                                        (parse-ctx-res-val-set! ctx (list sv_1814 sv_1816 sv_1818))
                                        sp_1817))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1819 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_1819
              (let ((sv_1820 (parse-ctx-res-val ctx)))
                (let ((sp_1821 (c99ds-ws ctx env sp_1819)))
                    (if sp_1821
                        (let ((sv_1822 (parse-ctx-res-val ctx)))
                          (let ((sp_1823 (c99ds-type_name ctx env sp_1821)))
                              (if sp_1823
                                  (let ((sv_1824 (parse-ctx-res-val ctx)))
                                    (let ((sp_1825 (peg-ds:lit1 ctx sp_1823 #\) ")" "')'")))
                                        (if sp_1825
                                            (let ((sv_1826 (parse-ctx-res-val ctx)))
                                              (let ((sp_1827 (c99ds-ws ctx env sp_1825)))
                                                  (if sp_1827
                                                      (let ((sv_1828 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1829 (peg-ds:lit1 ctx sp_1827 #\{ "{" "'{'")))
                                                            (if sp_1829
                                                                (let ((sv_1830 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1831 (c99ds-ws ctx env sp_1829)))
                                                                      (if sp_1831
                                                                          (let ((sv_1832 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1833 (let ((opt_1835 (let ((sp_1836 (c99ds-initializer_list ctx env sp_1831)))
                                                                                            (if sp_1836
                                                                                                (let ((sv_1837 (parse-ctx-res-val ctx)))
                                                                                                  (let ((sp_1838 (let ((opt_1840 (let ((sp_1841 (peg-ds:lit1 ctx sp_1836 #\, "," "','")))
                                                                                                                  (if sp_1841
                                                                                                                      (let ((sv_1842 (parse-ctx-res-val ctx)))
                                                                                                                        (let ((sp_1843 (c99ds-ws ctx env sp_1841)))
                                                                                                                            (if sp_1843
                                                                                                                                (let ((sv_1844 (parse-ctx-res-val ctx)))
                                                                                                                                  (begin
                                                                                                                                      (parse-ctx-res-val-set! ctx (list sv_1842 sv_1844))
                                                                                                                                      sp_1843))
                                                                                                                                #f)))
                                                                                                                      #f))))
                                                                                                            (if opt_1840
                                                                                                                opt_1840
                                                                                                                (begin (parse-ctx-res-val-set! ctx #f) sp_1836)))))
                                                                                                      (if sp_1838
                                                                                                          (let ((sv_1839 (parse-ctx-res-val ctx)))
                                                                                                            (begin
                                                                                                                (parse-ctx-res-val-set! ctx (list sv_1837 sv_1839))
                                                                                                                sp_1838))
                                                                                                          #f)))
                                                                                                #f))))
                                                                                      (if opt_1835
                                                                                          opt_1835
                                                                                          (begin (parse-ctx-res-val-set! ctx #f) sp_1831)))))
                                                                                (if sp_1833
                                                                                    (let ((sv_1834 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1845 (peg-ds:lit1 ctx sp_1833 #\} "}" "'}'")))
                                                                                          (if sp_1845
                                                                                              (let ((sv_1846 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1847 (c99ds-ws ctx env sp_1845)))
                                                                                                    (if sp_1847
                                                                                                        (let ((sv_1848 (parse-ctx-res-val ctx)))
                                                                                                          (begin
                                                                                                              (parse-ctx-res-val-set! ctx (list sv_1820 sv_1822 sv_1824 sv_1826 sv_1828 sv_1830 sv_1832 sv_1834 sv_1846 sv_1848))
                                                                                                              sp_1847))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (c99ds-primary_expr ctx env pos))))
      (if rdec_1849
          (c99ds-decorate-rule 'postfix_expr ctx env pos rdec_1849 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: argument_expr_list [memo]
(define (c99ds-argument_expr_list ctx env pos)
  (peg-ds:rule-memo ctx 'argument_expr_list pos
    (lambda ()
      (let ((rdec_1866 (let ((sp_1850 (let ((np_1852 (c99ds-assignment_expr ctx env pos)))
            (if np_1852
                (begin
                  (parse-ctx-res-val-set! ctx (cons 'first (parse-ctx-res-val ctx)))
                  np_1852)
                #f))))
      (if sp_1850
          (let ((sv_1851 (parse-ctx-res-val ctx)))
            (let ((sp_1853 (let ((np_1855 (let rloop_1856 ((rcur_1857 sp_1850) (racc_1858 '()))
                            (let ((rnext_1859 (let ((sp_1860 (peg-ds:lit1 ctx rcur_1857 #\, "," "','")))
                                  (if sp_1860
                                      (let ((sv_1861 (parse-ctx-res-val ctx)))
                                        (let ((sp_1862 (c99ds-ws ctx env sp_1860)))
                                            (if sp_1862
                                                (let ((sv_1863 (parse-ctx-res-val ctx)))
                                                  (let ((sp_1864 (c99ds-assignment_expr ctx env sp_1862)))
                                                      (if sp_1864
                                                          (let ((sv_1865 (parse-ctx-res-val ctx)))
                                                            (begin
                                                                (parse-ctx-res-val-set! ctx (list sv_1861 sv_1863 sv_1865))
                                                                sp_1864))
                                                          #f)))
                                                #f)))
                                      #f))))
                              (if (and rnext_1859 (> rnext_1859 rcur_1857))
                                  (rloop_1856 rnext_1859 (cons (parse-ctx-res-val ctx) racc_1858))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1858)) rcur_1857))))))
                      (if np_1855
                          (begin
                            (parse-ctx-res-val-set! ctx (cons 'rest (parse-ctx-res-val ctx)))
                            np_1855)
                          #f))))
                (if sp_1853
                    (let ((sv_1854 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_1851 sv_1854))
                          sp_1853))
                    #f)))
          #f))))
      (if rdec_1866
          (c99ds-decorate-rule 'argument_expr_list ctx env pos rdec_1866 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: primary_expr [lr]
(define (c99ds-primary_expr ctx env pos)
  (peg-ds:rule-lr ctx 'primary_expr pos
    (lambda ()
      (let ((rdec_1922 (or
      (let ((sp_1867 (peg-ds:lit ctx pos "__builtin_va_arg" 16 #\_ "'__builtin_va_arg'")))
          (if sp_1867
              (let ((sv_1868 (parse-ctx-res-val ctx)))
                (let ((sp_1869 (let ((pred_1871 (c99ds-ident_cont ctx env sp_1867)))
                          (if pred_1871
                              #f
                              (begin (parse-ctx-res-val-set! ctx #t) sp_1867)))))
                    (if sp_1869
                        (let ((sv_1870 (parse-ctx-res-val ctx)))
                          (let ((sp_1872 (c99ds-ws ctx env sp_1869)))
                              (if sp_1872
                                  (let ((sv_1873 (parse-ctx-res-val ctx)))
                                    (let ((sp_1874 (peg-ds:lit1 ctx sp_1872 #\( "(" "'('")))
                                        (if sp_1874
                                            (let ((sv_1875 (parse-ctx-res-val ctx)))
                                              (let ((sp_1876 (c99ds-ws ctx env sp_1874)))
                                                  (if sp_1876
                                                      (let ((sv_1877 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1878 (c99ds-assignment_expr ctx env sp_1876)))
                                                            (if sp_1878
                                                                (let ((sv_1879 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1880 (peg-ds:lit1 ctx sp_1878 #\, "," "','")))
                                                                      (if sp_1880
                                                                          (let ((sv_1881 (parse-ctx-res-val ctx)))
                                                                            (let ((sp_1882 (c99ds-ws ctx env sp_1880)))
                                                                                (if sp_1882
                                                                                    (let ((sv_1883 (parse-ctx-res-val ctx)))
                                                                                      (let ((sp_1884 (c99ds-type_name ctx env sp_1882)))
                                                                                          (if sp_1884
                                                                                              (let ((sv_1885 (parse-ctx-res-val ctx)))
                                                                                                (let ((sp_1886 (peg-ds:lit1 ctx sp_1884 #\) ")" "')'")))
                                                                                                    (if sp_1886
                                                                                                        (let ((sv_1887 (parse-ctx-res-val ctx)))
                                                                                                          (let ((sp_1888 (c99ds-ws ctx env sp_1886)))
                                                                                                              (if sp_1888
                                                                                                                  (let ((sv_1889 (parse-ctx-res-val ctx)))
                                                                                                                    (begin
                                                                                                                        (parse-ctx-res-val-set! ctx (list sv_1868 sv_1870 sv_1873 sv_1875 sv_1877 sv_1879 sv_1881 sv_1883 sv_1885 sv_1887 sv_1889))
                                                                                                                        sp_1888))
                                                                                                                  #f)))
                                                                                                        #f)))
                                                                                              #f)))
                                                                                    #f)))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1890 (c99ds-identifier ctx env pos)))
          (if sp_1890
              (let ((sv_1891 (parse-ctx-res-val ctx)))
                (let ((sp_1892 (c99ds-ws ctx env sp_1890)))
                    (if sp_1892
                        (let ((sv_1893 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1891 sv_1893))
                              sp_1892))
                        #f)))
              #f))
      (let ((sp_1894 (c99ds-constant ctx env pos)))
          (if sp_1894
              (let ((sv_1895 (parse-ctx-res-val ctx)))
                (let ((sp_1896 (c99ds-ws ctx env sp_1894)))
                    (if sp_1896
                        (let ((sv_1897 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_1895 sv_1897))
                              sp_1896))
                        #f)))
              #f))
      (let ((rp1_1902 (let ((sp_1904 (c99ds-string_literal ctx env pos)))
                (if sp_1904
                    (let ((sv_1905 (parse-ctx-res-val ctx)))
                      (let ((sp_1906 (c99ds-ws ctx env sp_1904)))
                          (if sp_1906
                              (let ((sv_1907 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_1905 sv_1907))
                                    sp_1906))
                              #f)))
                    #f))))
          (if rp1_1902
              (let ((rv1_1903 (parse-ctx-res-val ctx)))
                (if (<= rp1_1902 pos)
                    (begin (parse-ctx-res-val-set! ctx (list rv1_1903)) rp1_1902)
                    (let rloop_1898 ((rcur_1899 rp1_1902) (racc_1900 (list rv1_1903)))
                      (let ((rnext_1901 (let ((sp_1908 (c99ds-string_literal ctx env rcur_1899)))
                        (if sp_1908
                            (let ((sv_1909 (parse-ctx-res-val ctx)))
                              (let ((sp_1910 (c99ds-ws ctx env sp_1908)))
                                  (if sp_1910
                                      (let ((sv_1911 (parse-ctx-res-val ctx)))
                                        (begin
                                            (parse-ctx-res-val-set! ctx (list sv_1909 sv_1911))
                                            sp_1910))
                                      #f)))
                            #f))))
                        (if (and rnext_1901 (> rnext_1901 rcur_1899))
                            (rloop_1898 rnext_1901 (cons (parse-ctx-res-val ctx) racc_1900))
                            (begin (parse-ctx-res-val-set! ctx (reverse racc_1900)) rcur_1899))))))
              #f))
      (let ((sp_1912 (peg-ds:lit1 ctx pos #\( "(" "'('")))
          (if sp_1912
              (let ((sv_1913 (parse-ctx-res-val ctx)))
                (let ((sp_1914 (c99ds-ws ctx env sp_1912)))
                    (if sp_1914
                        (let ((sv_1915 (parse-ctx-res-val ctx)))
                          (let ((sp_1916 (c99ds-expr ctx env sp_1914)))
                              (if sp_1916
                                  (let ((sv_1917 (parse-ctx-res-val ctx)))
                                    (let ((sp_1918 (peg-ds:lit1 ctx sp_1916 #\) ")" "')'")))
                                        (if sp_1918
                                            (let ((sv_1919 (parse-ctx-res-val ctx)))
                                              (let ((sp_1920 (c99ds-ws ctx env sp_1918)))
                                                  (if sp_1920
                                                      (let ((sv_1921 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1913 sv_1915 sv_1917 sv_1919 sv_1921))
                                                            sp_1920))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f)))))
      (if rdec_1922
          (c99ds-decorate-rule 'primary_expr ctx env pos rdec_1922 (parse-ctx-res-val ctx))
          #f)))))

;;; Rule: identifier [bare]
(define (c99ds-identifier ctx env pos)
  (c99ds-leaf-identifier ctx env pos))

;;; Rule: ident_cont [bare]
(define (c99ds-ident_cont ctx env pos)
  (c99ds-leaf-ident-cont ctx env pos))

;;; Rule: c99_keyword [bare]
(define (c99ds-c99_keyword ctx env pos)
  (c99ds-leaf-keyword ctx env pos))

;;; Rule: constant [bare]
(define (c99ds-constant ctx env pos)
  (c99ds-leaf-constant ctx env pos))

;;; Rule: float_constant [bare]
(define (c99ds-float_constant ctx env pos)
  (or
      (let ((sp_1923 (or
                (peg-ds:lit ctx pos "0x" 2 #\0 "'0x'")
                (peg-ds:lit ctx pos "0X" 2 #\0 "'0X'"))))
          (if sp_1923
              (let ((sv_1924 (parse-ctx-res-val ctx)))
                (let ((sp_1925 (let rloop_1927 ((rcur_1928 sp_1923) (racc_1929 '()))
                          (let ((rnext_1930 (peg-ds:char-class ctx rcur_1928 *c99ds-cc-2* "[0-9a-fA-F]")))
                            (if (and rnext_1930 (> rnext_1930 rcur_1928))
                                (rloop_1927 rnext_1930 (cons (parse-ctx-res-val ctx) racc_1929))
                                (begin (parse-ctx-res-val-set! ctx (reverse racc_1929)) rcur_1928))))))
                    (if sp_1925
                        (let ((sv_1926 (parse-ctx-res-val ctx)))
                          (let ((sp_1931 (peg-ds:lit1 ctx sp_1925 #\. "." "'.'")))
                              (if sp_1931
                                  (let ((sv_1932 (parse-ctx-res-val ctx)))
                                    (let ((sp_1933 (let ((rp1_1939 (peg-ds:char-class ctx sp_1931 *c99ds-cc-2* "[0-9a-fA-F]")))
                                              (if rp1_1939
                                                  (let ((rv1_1940 (parse-ctx-res-val ctx)))
                                                    (if (<= rp1_1939 sp_1931)
                                                        (begin (parse-ctx-res-val-set! ctx (list rv1_1940)) rp1_1939)
                                                        (let rloop_1935 ((rcur_1936 rp1_1939) (racc_1937 (list rv1_1940)))
                                                          (let ((rnext_1938 (peg-ds:char-class ctx rcur_1936 *c99ds-cc-2* "[0-9a-fA-F]")))
                                                            (if (and rnext_1938 (> rnext_1938 rcur_1936))
                                                                (rloop_1935 rnext_1938 (cons (parse-ctx-res-val ctx) racc_1937))
                                                                (begin (parse-ctx-res-val-set! ctx (reverse racc_1937)) rcur_1936))))))
                                                  #f))))
                                        (if sp_1933
                                            (let ((sv_1934 (parse-ctx-res-val ctx)))
                                              (let ((sp_1941 (c99ds-binary_exponent ctx env sp_1933)))
                                                  (if sp_1941
                                                      (let ((sv_1942 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1943 (let ((opt_1945 (c99ds-float_suffix ctx env sp_1941)))
                                                                  (if opt_1945
                                                                      opt_1945
                                                                      (begin (parse-ctx-res-val-set! ctx #f) sp_1941)))))
                                                            (if sp_1943
                                                                (let ((sv_1944 (parse-ctx-res-val ctx)))
                                                                  (let ((sp_1946 (let ((pred_1948 (c99ds-ident_cont ctx env sp_1943)))
                                                                            (if pred_1948
                                                                                #f
                                                                                (begin (parse-ctx-res-val-set! ctx #t) sp_1943)))))
                                                                      (if sp_1946
                                                                          (let ((sv_1947 (parse-ctx-res-val ctx)))
                                                                            (begin
                                                                                (parse-ctx-res-val-set! ctx (list sv_1924 sv_1926 sv_1932 sv_1934 sv_1942 sv_1944 sv_1947))
                                                                                sp_1946))
                                                                          #f)))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1949 (or
                (peg-ds:lit ctx pos "0x" 2 #\0 "'0x'")
                (peg-ds:lit ctx pos "0X" 2 #\0 "'0X'"))))
          (if sp_1949
              (let ((sv_1950 (parse-ctx-res-val ctx)))
                (let ((sp_1951 (let ((rp1_1957 (peg-ds:char-class ctx sp_1949 *c99ds-cc-2* "[0-9a-fA-F]")))
                          (if rp1_1957
                              (let ((rv1_1958 (parse-ctx-res-val ctx)))
                                (if (<= rp1_1957 sp_1949)
                                    (begin (parse-ctx-res-val-set! ctx (list rv1_1958)) rp1_1957)
                                    (let rloop_1953 ((rcur_1954 rp1_1957) (racc_1955 (list rv1_1958)))
                                      (let ((rnext_1956 (peg-ds:char-class ctx rcur_1954 *c99ds-cc-2* "[0-9a-fA-F]")))
                                        (if (and rnext_1956 (> rnext_1956 rcur_1954))
                                            (rloop_1953 rnext_1956 (cons (parse-ctx-res-val ctx) racc_1955))
                                            (begin (parse-ctx-res-val-set! ctx (reverse racc_1955)) rcur_1954))))))
                              #f))))
                    (if sp_1951
                        (let ((sv_1952 (parse-ctx-res-val ctx)))
                          (let ((sp_1959 (let ((opt_1961 (peg-ds:lit1 ctx sp_1951 #\. "." "'.'")))
                                    (if opt_1961
                                        opt_1961
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_1951)))))
                              (if sp_1959
                                  (let ((sv_1960 (parse-ctx-res-val ctx)))
                                    (let ((sp_1962 (c99ds-binary_exponent ctx env sp_1959)))
                                        (if sp_1962
                                            (let ((sv_1963 (parse-ctx-res-val ctx)))
                                              (let ((sp_1964 (let ((opt_1966 (c99ds-float_suffix ctx env sp_1962)))
                                                        (if opt_1966
                                                            opt_1966
                                                            (begin (parse-ctx-res-val-set! ctx #f) sp_1962)))))
                                                  (if sp_1964
                                                      (let ((sv_1965 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1967 (let ((pred_1969 (c99ds-ident_cont ctx env sp_1964)))
                                                                  (if pred_1969
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_1964)))))
                                                            (if sp_1967
                                                                (let ((sv_1968 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1950 sv_1952 sv_1960 sv_1963 sv_1965 sv_1968))
                                                                      sp_1967))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1970 (let rloop_1972 ((rcur_1973 pos) (racc_1974 '()))
                (let ((rnext_1975 (peg-ds:char-class ctx rcur_1973 *c99ds-cc-3* "[0-9]")))
                  (if (and rnext_1975 (> rnext_1975 rcur_1973))
                      (rloop_1972 rnext_1975 (cons (parse-ctx-res-val ctx) racc_1974))
                      (begin (parse-ctx-res-val-set! ctx (reverse racc_1974)) rcur_1973))))))
          (if sp_1970
              (let ((sv_1971 (parse-ctx-res-val ctx)))
                (let ((sp_1976 (peg-ds:lit1 ctx sp_1970 #\. "." "'.'")))
                    (if sp_1976
                        (let ((sv_1977 (parse-ctx-res-val ctx)))
                          (let ((sp_1978 (let ((rp1_1984 (peg-ds:char-class ctx sp_1976 *c99ds-cc-3* "[0-9]")))
                                    (if rp1_1984
                                        (let ((rv1_1985 (parse-ctx-res-val ctx)))
                                          (if (<= rp1_1984 sp_1976)
                                              (begin (parse-ctx-res-val-set! ctx (list rv1_1985)) rp1_1984)
                                              (let rloop_1980 ((rcur_1981 rp1_1984) (racc_1982 (list rv1_1985)))
                                                (let ((rnext_1983 (peg-ds:char-class ctx rcur_1981 *c99ds-cc-3* "[0-9]")))
                                                  (if (and rnext_1983 (> rnext_1983 rcur_1981))
                                                      (rloop_1980 rnext_1983 (cons (parse-ctx-res-val ctx) racc_1982))
                                                      (begin (parse-ctx-res-val-set! ctx (reverse racc_1982)) rcur_1981))))))
                                        #f))))
                              (if sp_1978
                                  (let ((sv_1979 (parse-ctx-res-val ctx)))
                                    (let ((sp_1986 (let ((opt_1988 (c99ds-decimal_exponent ctx env sp_1978)))
                                              (if opt_1988
                                                  opt_1988
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_1978)))))
                                        (if sp_1986
                                            (let ((sv_1987 (parse-ctx-res-val ctx)))
                                              (let ((sp_1989 (let ((opt_1991 (c99ds-float_suffix ctx env sp_1986)))
                                                        (if opt_1991
                                                            opt_1991
                                                            (begin (parse-ctx-res-val-set! ctx #f) sp_1986)))))
                                                  (if sp_1989
                                                      (let ((sv_1990 (parse-ctx-res-val ctx)))
                                                        (let ((sp_1992 (let ((pred_1994 (c99ds-ident_cont ctx env sp_1989)))
                                                                  (if pred_1994
                                                                      #f
                                                                      (begin (parse-ctx-res-val-set! ctx #t) sp_1989)))))
                                                            (if sp_1992
                                                                (let ((sv_1993 (parse-ctx-res-val ctx)))
                                                                  (begin
                                                                      (parse-ctx-res-val-set! ctx (list sv_1971 sv_1977 sv_1979 sv_1987 sv_1990 sv_1993))
                                                                      sp_1992))
                                                                #f)))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_1995 (let ((rp1_2001 (peg-ds:char-class ctx pos *c99ds-cc-3* "[0-9]")))
                (if rp1_2001
                    (let ((rv1_2002 (parse-ctx-res-val ctx)))
                      (if (<= rp1_2001 pos)
                          (begin (parse-ctx-res-val-set! ctx (list rv1_2002)) rp1_2001)
                          (let rloop_1997 ((rcur_1998 rp1_2001) (racc_1999 (list rv1_2002)))
                            (let ((rnext_2000 (peg-ds:char-class ctx rcur_1998 *c99ds-cc-3* "[0-9]")))
                              (if (and rnext_2000 (> rnext_2000 rcur_1998))
                                  (rloop_1997 rnext_2000 (cons (parse-ctx-res-val ctx) racc_1999))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_1999)) rcur_1998))))))
                    #f))))
          (if sp_1995
              (let ((sv_1996 (parse-ctx-res-val ctx)))
                (let ((sp_2003 (peg-ds:lit1 ctx sp_1995 #\. "." "'.'")))
                    (if sp_2003
                        (let ((sv_2004 (parse-ctx-res-val ctx)))
                          (let ((sp_2005 (let ((opt_2007 (c99ds-decimal_exponent ctx env sp_2003)))
                                    (if opt_2007
                                        opt_2007
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_2003)))))
                              (if sp_2005
                                  (let ((sv_2006 (parse-ctx-res-val ctx)))
                                    (let ((sp_2008 (let ((opt_2010 (c99ds-float_suffix ctx env sp_2005)))
                                              (if opt_2010
                                                  opt_2010
                                                  (begin (parse-ctx-res-val-set! ctx #f) sp_2005)))))
                                        (if sp_2008
                                            (let ((sv_2009 (parse-ctx-res-val ctx)))
                                              (let ((sp_2011 (let ((pred_2013 (c99ds-ident_cont ctx env sp_2008)))
                                                        (if pred_2013
                                                            #f
                                                            (begin (parse-ctx-res-val-set! ctx #t) sp_2008)))))
                                                  (if sp_2011
                                                      (let ((sv_2012 (parse-ctx-res-val ctx)))
                                                        (begin
                                                            (parse-ctx-res-val-set! ctx (list sv_1996 sv_2004 sv_2006 sv_2009 sv_2012))
                                                            sp_2011))
                                                      #f)))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_2014 (let ((rp1_2020 (peg-ds:char-class ctx pos *c99ds-cc-3* "[0-9]")))
                (if rp1_2020
                    (let ((rv1_2021 (parse-ctx-res-val ctx)))
                      (if (<= rp1_2020 pos)
                          (begin (parse-ctx-res-val-set! ctx (list rv1_2021)) rp1_2020)
                          (let rloop_2016 ((rcur_2017 rp1_2020) (racc_2018 (list rv1_2021)))
                            (let ((rnext_2019 (peg-ds:char-class ctx rcur_2017 *c99ds-cc-3* "[0-9]")))
                              (if (and rnext_2019 (> rnext_2019 rcur_2017))
                                  (rloop_2016 rnext_2019 (cons (parse-ctx-res-val ctx) racc_2018))
                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_2018)) rcur_2017))))))
                    #f))))
          (if sp_2014
              (let ((sv_2015 (parse-ctx-res-val ctx)))
                (let ((sp_2022 (c99ds-decimal_exponent ctx env sp_2014)))
                    (if sp_2022
                        (let ((sv_2023 (parse-ctx-res-val ctx)))
                          (let ((sp_2024 (let ((opt_2026 (c99ds-float_suffix ctx env sp_2022)))
                                    (if opt_2026
                                        opt_2026
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_2022)))))
                              (if sp_2024
                                  (let ((sv_2025 (parse-ctx-res-val ctx)))
                                    (let ((sp_2027 (let ((pred_2029 (c99ds-ident_cont ctx env sp_2024)))
                                              (if pred_2029
                                                  #f
                                                  (begin (parse-ctx-res-val-set! ctx #t) sp_2024)))))
                                        (if sp_2027
                                            (let ((sv_2028 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_2015 sv_2023 sv_2025 sv_2028))
                                                  sp_2027))
                                            #f)))
                                  #f)))
                        #f)))
              #f))))

;;; Rule: decimal_exponent [bare]
(define (c99ds-decimal_exponent ctx env pos)
  (let ((sp_2030 (or
            (peg-ds:lit1 ctx pos #\e "e" "'e'")
            (peg-ds:lit1 ctx pos #\E "E" "'E'"))))
      (if sp_2030
          (let ((sv_2031 (parse-ctx-res-val ctx)))
            (let ((sp_2032 (let ((opt_2034 (or
                            (peg-ds:lit1 ctx sp_2030 #\+ "+" "'+'")
                            (peg-ds:lit1 ctx sp_2030 #\- "-" "'-'"))))
                      (if opt_2034
                          opt_2034
                          (begin (parse-ctx-res-val-set! ctx #f) sp_2030)))))
                (if sp_2032
                    (let ((sv_2033 (parse-ctx-res-val ctx)))
                      (let ((sp_2035 (let ((rp1_2041 (peg-ds:char-class ctx sp_2032 *c99ds-cc-3* "[0-9]")))
                                (if rp1_2041
                                    (let ((rv1_2042 (parse-ctx-res-val ctx)))
                                      (if (<= rp1_2041 sp_2032)
                                          (begin (parse-ctx-res-val-set! ctx (list rv1_2042)) rp1_2041)
                                          (let rloop_2037 ((rcur_2038 rp1_2041) (racc_2039 (list rv1_2042)))
                                            (let ((rnext_2040 (peg-ds:char-class ctx rcur_2038 *c99ds-cc-3* "[0-9]")))
                                              (if (and rnext_2040 (> rnext_2040 rcur_2038))
                                                  (rloop_2037 rnext_2040 (cons (parse-ctx-res-val ctx) racc_2039))
                                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_2039)) rcur_2038))))))
                                    #f))))
                          (if sp_2035
                              (let ((sv_2036 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_2031 sv_2033 sv_2036))
                                    sp_2035))
                              #f)))
                    #f)))
          #f)))

;;; Rule: binary_exponent [bare]
(define (c99ds-binary_exponent ctx env pos)
  (let ((sp_2043 (or
            (peg-ds:lit1 ctx pos #\p "p" "'p'")
            (peg-ds:lit1 ctx pos #\P "P" "'P'"))))
      (if sp_2043
          (let ((sv_2044 (parse-ctx-res-val ctx)))
            (let ((sp_2045 (let ((opt_2047 (or
                            (peg-ds:lit1 ctx sp_2043 #\+ "+" "'+'")
                            (peg-ds:lit1 ctx sp_2043 #\- "-" "'-'"))))
                      (if opt_2047
                          opt_2047
                          (begin (parse-ctx-res-val-set! ctx #f) sp_2043)))))
                (if sp_2045
                    (let ((sv_2046 (parse-ctx-res-val ctx)))
                      (let ((sp_2048 (let ((rp1_2054 (peg-ds:char-class ctx sp_2045 *c99ds-cc-3* "[0-9]")))
                                (if rp1_2054
                                    (let ((rv1_2055 (parse-ctx-res-val ctx)))
                                      (if (<= rp1_2054 sp_2045)
                                          (begin (parse-ctx-res-val-set! ctx (list rv1_2055)) rp1_2054)
                                          (let rloop_2050 ((rcur_2051 rp1_2054) (racc_2052 (list rv1_2055)))
                                            (let ((rnext_2053 (peg-ds:char-class ctx rcur_2051 *c99ds-cc-3* "[0-9]")))
                                              (if (and rnext_2053 (> rnext_2053 rcur_2051))
                                                  (rloop_2050 rnext_2053 (cons (parse-ctx-res-val ctx) racc_2052))
                                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_2052)) rcur_2051))))))
                                    #f))))
                          (if sp_2048
                              (let ((sv_2049 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_2044 sv_2046 sv_2049))
                                    sp_2048))
                              #f)))
                    #f)))
          #f)))

;;; Rule: float_suffix [bare]
(define (c99ds-float_suffix ctx env pos)
  (or
      (peg-ds:lit1 ctx pos #\f "f" "'f'")
      (peg-ds:lit1 ctx pos #\F "F" "'F'")
      (peg-ds:lit1 ctx pos #\l "l" "'l'")
      (peg-ds:lit1 ctx pos #\L "L" "'L'")))

;;; Rule: integer_constant [bare]
(define (c99ds-integer_constant ctx env pos)
  (or
      (let ((sp_2056 (or
                (peg-ds:lit ctx pos "0x" 2 #\0 "'0x'")
                (peg-ds:lit ctx pos "0X" 2 #\0 "'0X'"))))
          (if sp_2056
              (let ((sv_2057 (parse-ctx-res-val ctx)))
                (let ((sp_2058 (let ((rp1_2064 (peg-ds:char-class ctx sp_2056 *c99ds-cc-2* "[0-9a-fA-F]")))
                          (if rp1_2064
                              (let ((rv1_2065 (parse-ctx-res-val ctx)))
                                (if (<= rp1_2064 sp_2056)
                                    (begin (parse-ctx-res-val-set! ctx (list rv1_2065)) rp1_2064)
                                    (let rloop_2060 ((rcur_2061 rp1_2064) (racc_2062 (list rv1_2065)))
                                      (let ((rnext_2063 (peg-ds:char-class ctx rcur_2061 *c99ds-cc-2* "[0-9a-fA-F]")))
                                        (if (and rnext_2063 (> rnext_2063 rcur_2061))
                                            (rloop_2060 rnext_2063 (cons (parse-ctx-res-val ctx) racc_2062))
                                            (begin (parse-ctx-res-val-set! ctx (reverse racc_2062)) rcur_2061))))))
                              #f))))
                    (if sp_2058
                        (let ((sv_2059 (parse-ctx-res-val ctx)))
                          (let ((sp_2066 (let ((opt_2068 (c99ds-integer_suffix ctx env sp_2058)))
                                    (if opt_2068
                                        opt_2068
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_2058)))))
                              (if sp_2066
                                  (let ((sv_2067 (parse-ctx-res-val ctx)))
                                    (let ((sp_2069 (let ((pred_2071 (c99ds-ident_cont ctx env sp_2066)))
                                              (if pred_2071
                                                  #f
                                                  (begin (parse-ctx-res-val-set! ctx #t) sp_2066)))))
                                        (if sp_2069
                                            (let ((sv_2070 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_2057 sv_2059 sv_2067 sv_2070))
                                                  sp_2069))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_2072 (peg-ds:lit1 ctx pos #\0 "0" "'0'")))
          (if sp_2072
              (let ((sv_2073 (parse-ctx-res-val ctx)))
                (let ((sp_2074 (let rloop_2076 ((rcur_2077 sp_2072) (racc_2078 '()))
                          (let ((rnext_2079 (peg-ds:char-class ctx rcur_2077 *c99ds-cc-4* "[0-7]")))
                            (if (and rnext_2079 (> rnext_2079 rcur_2077))
                                (rloop_2076 rnext_2079 (cons (parse-ctx-res-val ctx) racc_2078))
                                (begin (parse-ctx-res-val-set! ctx (reverse racc_2078)) rcur_2077))))))
                    (if sp_2074
                        (let ((sv_2075 (parse-ctx-res-val ctx)))
                          (let ((sp_2080 (let ((opt_2082 (c99ds-integer_suffix ctx env sp_2074)))
                                    (if opt_2082
                                        opt_2082
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_2074)))))
                              (if sp_2080
                                  (let ((sv_2081 (parse-ctx-res-val ctx)))
                                    (let ((sp_2083 (let ((pred_2085 (c99ds-ident_cont ctx env sp_2080)))
                                              (if pred_2085
                                                  #f
                                                  (begin (parse-ctx-res-val-set! ctx #t) sp_2080)))))
                                        (if sp_2083
                                            (let ((sv_2084 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_2073 sv_2075 sv_2081 sv_2084))
                                                  sp_2083))
                                            #f)))
                                  #f)))
                        #f)))
              #f))
      (let ((sp_2086 (peg-ds:char-class ctx pos *c99ds-cc-5* "[1-9]")))
          (if sp_2086
              (let ((sv_2087 (parse-ctx-res-val ctx)))
                (let ((sp_2088 (let rloop_2090 ((rcur_2091 sp_2086) (racc_2092 '()))
                          (let ((rnext_2093 (peg-ds:char-class ctx rcur_2091 *c99ds-cc-3* "[0-9]")))
                            (if (and rnext_2093 (> rnext_2093 rcur_2091))
                                (rloop_2090 rnext_2093 (cons (parse-ctx-res-val ctx) racc_2092))
                                (begin (parse-ctx-res-val-set! ctx (reverse racc_2092)) rcur_2091))))))
                    (if sp_2088
                        (let ((sv_2089 (parse-ctx-res-val ctx)))
                          (let ((sp_2094 (let ((opt_2096 (c99ds-integer_suffix ctx env sp_2088)))
                                    (if opt_2096
                                        opt_2096
                                        (begin (parse-ctx-res-val-set! ctx #f) sp_2088)))))
                              (if sp_2094
                                  (let ((sv_2095 (parse-ctx-res-val ctx)))
                                    (let ((sp_2097 (let ((pred_2099 (c99ds-ident_cont ctx env sp_2094)))
                                              (if pred_2099
                                                  #f
                                                  (begin (parse-ctx-res-val-set! ctx #t) sp_2094)))))
                                        (if sp_2097
                                            (let ((sv_2098 (parse-ctx-res-val ctx)))
                                              (begin
                                                  (parse-ctx-res-val-set! ctx (list sv_2087 sv_2089 sv_2095 sv_2098))
                                                  sp_2097))
                                            #f)))
                                  #f)))
                        #f)))
              #f))))

;;; Rule: integer_suffix [bare]
(define (c99ds-integer_suffix ctx env pos)
  (or
      (let ((sp_2100 (or
                (peg-ds:lit1 ctx pos #\u "u" "'u'")
                (peg-ds:lit1 ctx pos #\U "U" "'U'"))))
          (if sp_2100
              (let ((sv_2101 (parse-ctx-res-val ctx)))
                (let ((sp_2102 (let ((opt_2104 (or
                                (peg-ds:lit ctx sp_2100 "ll" 2 #\l "'ll'")
                                (peg-ds:lit ctx sp_2100 "LL" 2 #\L "'LL'")
                                (peg-ds:lit1 ctx sp_2100 #\l "l" "'l'")
                                (peg-ds:lit1 ctx sp_2100 #\L "L" "'L'"))))
                          (if opt_2104
                              opt_2104
                              (begin (parse-ctx-res-val-set! ctx #f) sp_2100)))))
                    (if sp_2102
                        (let ((sv_2103 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_2101 sv_2103))
                              sp_2102))
                        #f)))
              #f))
      (let ((sp_2105 (or
                (peg-ds:lit ctx pos "ll" 2 #\l "'ll'")
                (peg-ds:lit ctx pos "LL" 2 #\L "'LL'")
                (peg-ds:lit1 ctx pos #\l "l" "'l'")
                (peg-ds:lit1 ctx pos #\L "L" "'L'"))))
          (if sp_2105
              (let ((sv_2106 (parse-ctx-res-val ctx)))
                (let ((sp_2107 (let ((opt_2109 (or
                                (peg-ds:lit1 ctx sp_2105 #\u "u" "'u'")
                                (peg-ds:lit1 ctx sp_2105 #\U "U" "'U'"))))
                          (if opt_2109
                              opt_2109
                              (begin (parse-ctx-res-val-set! ctx #f) sp_2105)))))
                    (if sp_2107
                        (let ((sv_2108 (parse-ctx-res-val ctx)))
                          (begin
                              (parse-ctx-res-val-set! ctx (list sv_2106 sv_2108))
                              sp_2107))
                        #f)))
              #f))))

;;; Rule: char_constant [bare]
(define (c99ds-char_constant ctx env pos)
  (let ((sp_2110 (let ((opt_2112 (peg-ds:lit1 ctx pos #\L "L" "'L'")))
            (if opt_2112
                opt_2112
                (begin (parse-ctx-res-val-set! ctx #f) pos)))))
      (if sp_2110
          (let ((sv_2111 (parse-ctx-res-val ctx)))
            (let ((sp_2113 (peg-ds:lit1 ctx sp_2110 #\' "'" "'''")))
                (if sp_2113
                    (let ((sv_2114 (parse-ctx-res-val ctx)))
                      (let ((sp_2115 (let ((rp1_2121 (or
                                      (c99ds-escape_seq ctx env sp_2113)
                                      (peg-ds:char-class ctx sp_2113 *c99ds-cc-6* "[^'\\\\\\r\\n]"))))
                                (if rp1_2121
                                    (let ((rv1_2122 (parse-ctx-res-val ctx)))
                                      (if (<= rp1_2121 sp_2113)
                                          (begin (parse-ctx-res-val-set! ctx (list rv1_2122)) rp1_2121)
                                          (let rloop_2117 ((rcur_2118 rp1_2121) (racc_2119 (list rv1_2122)))
                                            (let ((rnext_2120 (or
                                              (c99ds-escape_seq ctx env rcur_2118)
                                              (peg-ds:char-class ctx rcur_2118 *c99ds-cc-6* "[^'\\\\\\r\\n]"))))
                                              (if (and rnext_2120 (> rnext_2120 rcur_2118))
                                                  (rloop_2117 rnext_2120 (cons (parse-ctx-res-val ctx) racc_2119))
                                                  (begin (parse-ctx-res-val-set! ctx (reverse racc_2119)) rcur_2118))))))
                                    #f))))
                          (if sp_2115
                              (let ((sv_2116 (parse-ctx-res-val ctx)))
                                (let ((sp_2123 (peg-ds:lit1 ctx sp_2115 #\' "'" "'''")))
                                    (if sp_2123
                                        (let ((sv_2124 (parse-ctx-res-val ctx)))
                                          (begin
                                              (parse-ctx-res-val-set! ctx (list sv_2111 sv_2114 sv_2116 sv_2124))
                                              sp_2123))
                                        #f)))
                              #f)))
                    #f)))
          #f)))

;;; Rule: string_literal [bare]
(define (c99ds-string_literal ctx env pos)
  (c99ds-leaf-string-literal ctx env pos))

;;; Rule: escape_seq [bare]
(define (c99ds-escape_seq ctx env pos)
  (let ((sp_2125 (peg-ds:lit1 ctx pos #\\ "\\" "'\\'")))
      (if sp_2125
          (let ((sv_2126 (parse-ctx-res-val ctx)))
            (let ((sp_2127 (peg-ds:any-char ctx sp_2125)))
                (if sp_2127
                    (let ((sv_2128 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_2126 sv_2128))
                          sp_2127))
                    #f)))
          #f)))

;;; Rule: c99_punctuator [bare]
(define (c99ds-c99_punctuator ctx env pos)
  (or
      (peg-ds:lit ctx pos "<<=" 3 #\< "'<<='")
      (peg-ds:lit ctx pos ">>=" 3 #\> "'>>='")
      (peg-ds:lit ctx pos "..." 3 #\. "'...'")
      (peg-ds:lit ctx pos "->" 2 #\- "'->'")
      (peg-ds:lit ctx pos "++" 2 #\+ "'++'")
      (peg-ds:lit ctx pos "--" 2 #\- "'--'")
      (peg-ds:lit ctx pos "<<" 2 #\< "'<<'")
      (peg-ds:lit ctx pos ">>" 2 #\> "'>>'")
      (peg-ds:lit ctx pos "<=" 2 #\< "'<='")
      (peg-ds:lit ctx pos ">=" 2 #\> "'>='")
      (peg-ds:lit ctx pos "==" 2 #\= "'=='")
      (peg-ds:lit ctx pos "!=" 2 #\! "'!='")
      (peg-ds:lit ctx pos "&&" 2 #\& "'&&'")
      (peg-ds:lit ctx pos "||" 2 #\| "'||'")
      (peg-ds:lit ctx pos "+=" 2 #\+ "'+='")
      (peg-ds:lit ctx pos "-=" 2 #\- "'-='")
      (peg-ds:lit ctx pos "*=" 2 #\* "'*='")
      (peg-ds:lit ctx pos "/=" 2 #\/ "'/='")
      (peg-ds:lit ctx pos "%=" 2 #\% "'%='")
      (peg-ds:lit ctx pos "&=" 2 #\& "'&='")
      (peg-ds:lit ctx pos "^=" 2 #\^ "'^='")
      (peg-ds:lit ctx pos "|=" 2 #\| "'|='")
      (peg-ds:lit ctx pos "##" 2 #\# "'##'")
      (peg-ds:lit ctx pos "<:" 2 #\< "'<:'")
      (peg-ds:lit ctx pos ":>" 2 #\: "':>'")
      (peg-ds:lit ctx pos "<%" 2 #\< "'<%'")
      (peg-ds:lit ctx pos "%>" 2 #\% "'%>'")
      (peg-ds:lit ctx pos "%:" 2 #\% "'%:'")
      (peg-ds:lit1 ctx pos #\[ "[" "'['")
      (peg-ds:lit1 ctx pos #\] "]" "']'")
      (peg-ds:lit1 ctx pos #\( "(" "'('")
      (peg-ds:lit1 ctx pos #\) ")" "')'")
      (peg-ds:lit1 ctx pos #\{ "{" "'{'")
      (peg-ds:lit1 ctx pos #\} "}" "'}'")
      (peg-ds:lit1 ctx pos #\. "." "'.'")
      (peg-ds:lit1 ctx pos #\& "&" "'&'")
      (peg-ds:lit1 ctx pos #\* "*" "'*'")
      (peg-ds:lit1 ctx pos #\+ "+" "'+'")
      (peg-ds:lit1 ctx pos #\- "-" "'-'")
      (peg-ds:lit1 ctx pos #\~ "~" "'~'")
      (peg-ds:lit1 ctx pos #\! "!" "'!'")
      (peg-ds:lit1 ctx pos #\/ "/" "'/'")
      (peg-ds:lit1 ctx pos #\% "%" "'%'")
      (peg-ds:lit1 ctx pos #\< "<" "'<'")
      (peg-ds:lit1 ctx pos #\> ">" "'>'")
      (peg-ds:lit1 ctx pos #\^ "^" "'^'")
      (peg-ds:lit1 ctx pos #\| "|" "'|'")
      (peg-ds:lit1 ctx pos #\? "?" "'?'")
      (peg-ds:lit1 ctx pos #\: ":" "':'")
      (peg-ds:lit1 ctx pos #\; ";" "';'")
      (peg-ds:lit1 ctx pos #\= "=" "'='")
      (peg-ds:lit1 ctx pos #\, "," "','")
      (peg-ds:lit1 ctx pos #\# "#" "'#'")))

;;; Rule: c99_raw_token [bare]
(define (c99ds-c99_raw_token ctx env pos)
  (or
      (let ((np_2129 (c99ds-char_constant ctx env pos)))
          (if np_2129
              (begin
                (parse-ctx-res-val-set! ctx (cons 'ch (parse-ctx-res-val ctx)))
                np_2129)
              #f))
      (let ((np_2130 (c99ds-string_literal ctx env pos)))
          (if np_2130
              (begin
                (parse-ctx-res-val-set! ctx (cons 'str (parse-ctx-res-val ctx)))
                np_2130)
              #f))
      (let ((np_2131 (c99ds-c99_keyword ctx env pos)))
          (if np_2131
              (begin
                (parse-ctx-res-val-set! ctx (cons 'kw (parse-ctx-res-val ctx)))
                np_2131)
              #f))
      (let ((np_2132 (c99ds-identifier ctx env pos)))
          (if np_2132
              (begin
                (parse-ctx-res-val-set! ctx (cons 'id (parse-ctx-res-val ctx)))
                np_2132)
              #f))
      (let ((np_2133 (c99ds-float_constant ctx env pos)))
          (if np_2133
              (begin
                (parse-ctx-res-val-set! ctx (cons 'flt (parse-ctx-res-val ctx)))
                np_2133)
              #f))
      (let ((np_2134 (c99ds-integer_constant ctx env pos)))
          (if np_2134
              (begin
                (parse-ctx-res-val-set! ctx (cons 'int (parse-ctx-res-val ctx)))
                np_2134)
              #f))
      (let ((np_2135 (c99ds-c99_punctuator ctx env pos)))
          (if np_2135
              (begin
                (parse-ctx-res-val-set! ctx (cons 'punct (parse-ctx-res-val ctx)))
                np_2135)
              #f))))

;;; Rule: ws [bare]
(define (c99ds-ws ctx env pos)
  (c99ds-leaf-ws ctx env pos))

;;; Rule: line_comment [bare]
(define (c99ds-line_comment ctx env pos)
  (let ((sp_2136 (peg-ds:lit ctx pos "//" 2 #\/ "'//'")))
      (if sp_2136
          (let ((sv_2137 (parse-ctx-res-val ctx)))
            (let ((sp_2138 (let rloop_2140 ((rcur_2141 sp_2136) (racc_2142 '()))
                      (let ((rnext_2143 (peg-ds:char-class ctx rcur_2141 *c99ds-cc-9* "[^\\r\\n]")))
                        (if (and rnext_2143 (> rnext_2143 rcur_2141))
                            (rloop_2140 rnext_2143 (cons (parse-ctx-res-val ctx) racc_2142))
                            (begin (parse-ctx-res-val-set! ctx (reverse racc_2142)) rcur_2141))))))
                (if sp_2138
                    (let ((sv_2139 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_2137 sv_2139))
                          sp_2138))
                    #f)))
          #f)))

;;; Rule: block_comment [bare]
(define (c99ds-block_comment ctx env pos)
  (let ((sp_2144 (peg-ds:lit ctx pos "/*" 2 #\/ "'/*'")))
      (if sp_2144
          (let ((sv_2145 (parse-ctx-res-val ctx)))
            (let ((sp_2146 (let rloop_2148 ((rcur_2149 sp_2144) (racc_2150 '()))
                      (let ((rnext_2151 (let ((sp_2152 (let ((pred_2154 (peg-ds:lit ctx rcur_2149 "*/" 2 #\* "'*/'")))
                                  (if pred_2154
                                      #f
                                      (begin (parse-ctx-res-val-set! ctx #t) rcur_2149)))))
                            (if sp_2152
                                (let ((sv_2153 (parse-ctx-res-val ctx)))
                                  (let ((sp_2155 (peg-ds:any-char ctx sp_2152)))
                                      (if sp_2155
                                          (let ((sv_2156 (parse-ctx-res-val ctx)))
                                            (begin
                                                (parse-ctx-res-val-set! ctx (list sv_2153 sv_2156))
                                                sp_2155))
                                          #f)))
                                #f))))
                        (if (and rnext_2151 (> rnext_2151 rcur_2149))
                            (rloop_2148 rnext_2151 (cons (parse-ctx-res-val ctx) racc_2150))
                            (begin (parse-ctx-res-val-set! ctx (reverse racc_2150)) rcur_2149))))))
                (if sp_2146
                    (let ((sv_2147 (parse-ctx-res-val ctx)))
                      (let ((sp_2157 (peg-ds:lit ctx sp_2146 "*/" 2 #\* "'*/'")))
                          (if sp_2157
                              (let ((sv_2158 (parse-ctx-res-val ctx)))
                                (begin
                                    (parse-ctx-res-val-set! ctx (list sv_2145 sv_2147 sv_2158))
                                    sp_2157))
                              #f)))
                    #f)))
          #f)))

;;; Rule: pp_line [bare]
(define (c99ds-pp_line ctx env pos)
  (let ((sp_2159 (peg-ds:lit1 ctx pos #\# "#" "'#'")))
      (if sp_2159
          (let ((sv_2160 (parse-ctx-res-val ctx)))
            (let ((sp_2161 (let rloop_2163 ((rcur_2164 sp_2159) (racc_2165 '()))
                      (let ((rnext_2166 (peg-ds:char-class ctx rcur_2164 *c99ds-cc-9* "[^\\r\\n]")))
                        (if (and rnext_2166 (> rnext_2166 rcur_2164))
                            (rloop_2163 rnext_2166 (cons (parse-ctx-res-val ctx) racc_2165))
                            (begin (parse-ctx-res-val-set! ctx (reverse racc_2165)) rcur_2164))))))
                (if sp_2161
                    (let ((sv_2162 (parse-ctx-res-val ctx)))
                      (begin
                          (parse-ctx-res-val-set! ctx (list sv_2160 sv_2162))
                          sp_2161))
                    #f)))
          #f)))

;;; Top-Level Direct-Style Parser Entrypoints
(define c99ds-parse-partial
  (case-lambda
    ((env text)
     (peg-ds:parse-partial (lambda (ctx pos) (c99ds-translation_unit ctx env pos)) text))
    ((env text start-pos)
     (peg-ds:parse-partial (lambda (ctx pos) (c99ds-translation_unit ctx env pos)) text start-pos))))

(define (c99ds-parse env text)
  (peg-ds:parse (lambda (ctx pos) (c99ds-translation_unit ctx env pos)) text))
