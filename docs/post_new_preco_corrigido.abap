METHOD post_new_preco.
* ─────────────────────────────────────────────────────────────────────────
* Correção principal em relação à versão anterior:
*   O método antigo chamava CALL TRANSACTION 'VK11'/'VK12' e nunca olhava o
*   resultado (it_msg era preenchido e nunca lido). Se a BDC batesse em uma
*   tela inesperada (chave duplicada, pop-up de sobreposição de vigência,
*   material bloqueado, campo obrigatório, etc.), o registro simplesmente
*   não era gravado no SAP — mas a function sempre respondia '{"ok":true}',
*   então o Pole Price achava que tinha dado tudo certo.
*
*   Agora, depois de cada CALL TRANSACTION, procura mensagens tipo 'E'/'A'
*   em it_msg. Se encontrar, o material entra na lista de falhas (it_falhas)
*   com o texto da mensagem de erro. No fim, a resposta JSON passa a incluir
*   "falhas": [ { "matnr": "...", "erro": "..." }, ... ] — vazio quando tudo
*   deu certo. O Pole Price usa esse campo para avisar quais materiais não
*   foram realmente atualizados no SAP.
*
*   Segunda correção: o campo GKWRT (valor superior da faixa de preço) era
*   sempre gravado igual ao KBETR (preço), fixo no código. Agora vem no
*   payload como campo próprio (ls_item-gkwrt), editável material a
*   material no Pole Price — junto com MXWRT (valor inferior).
* ─────────────────────────────────────────────────────────────────────────

  TYPES: BEGIN OF ty_item,
           matnr  TYPE string,
           kbetr  TYPE string,
           konwa  TYPE string,
           kmein  TYPE string,
           krech  TYPE string,
           datab  TYPE string,
           datbi  TYPE string,
           mxwrt  TYPE string,
           gkwrt  TYPE string,
           status TYPE string,
         END OF ty_item.

  TYPES: ty_t_items TYPE STANDARD TABLE OF ty_item WITH EMPTY KEY.

  TYPES: BEGIN OF ty_request,
           action TYPE string,
           pltyp  TYPE string,
           items  TYPE ty_t_items,
         END OF ty_request.

  TYPES: BEGIN OF ty_falha,
           matnr TYPE string,
           erro  TYPE string,
         END OF ty_falha.

  DATA: ls_request TYPE ty_request,
        lv_body    TYPE string.

  DATA: it_bdcdata TYPE TABLE OF bdcdata,
        wa_bdcdata TYPE bdcdata,
        it_msg     TYPE TABLE OF bdcmsgcoll,
        it_falhas  TYPE STANDARD TABLE OF ty_falha,
        lv_ok      TYPE abap_bool.

  DATA(lv_method) = mo_request->get_header_field( '~request_method' ).
  IF lv_method <> 'POST'.
    mo_response->set_status( 405 ).
    RETURN.
  ENDIF.

  lv_body = mo_request->get_entity( )->get_string_data( ).

  /ui2/cl_json=>deserialize(
    EXPORTING json = lv_body
    CHANGING  data = ls_request ).

  IF ls_request-action IS INITIAL OR ls_request-pltyp IS INITIAL.
    mo_response->set_status( 400 ).
    RETURN.
  ENDIF.

  DEFINE add_bdc_header.
    CLEAR wa_bdcdata.
    wa_bdcdata-program  = &2.
    wa_bdcdata-dynpro   = &3.
    wa_bdcdata-dynbegin = &1.
    APPEND wa_bdcdata TO it_bdcdata.
  END-OF-DEFINITION.

  DEFINE add_bdc_body.
    CLEAR wa_bdcdata.
    wa_bdcdata-fnam     = &1.
    wa_bdcdata-fval     = &2.
    APPEND wa_bdcdata TO it_bdcdata.
  END-OF-DEFINITION.

  LOOP AT ls_request-items INTO DATA(ls_item).

    DATA: vl_saida TYPE matnr.

    CALL FUNCTION 'CONVERSION_EXIT_ALPHA_INPUT'
      EXPORTING
        input  = ls_item-matnr
      IMPORTING
        output = vl_saida.

    SELECT SINGLE MAX( knumh )
      FROM a913
      INTO @DATA(vl_lista)
      WHERE matnr EQ @vl_saida
      AND pltyp EQ @ls_request-pltyp.

    SELECT SINGLE loevm_ko
      FROM konp
      INTO @DATA(vl_bloq)
      WHERE knumh EQ @vl_lista.

    CLEAR it_bdcdata.

    DATA(ls_datab) = |{ ls_item-datab+6(2) }.{ ls_item-datab+4(2) }.{ ls_item-datab(4) }|.
    DATA(ls_datbi) = |{ ls_item-datbi+6(2) }.{ ls_item-datbi+4(2) }.{ ls_item-datbi(4) }|.

    "========================
    " VK11
    "========================

    DATA: ls_mein  TYPE char3,
          ls_msehi TYPE msehi.

    ls_msehi = ls_item-kmein.

    CALL FUNCTION 'UNIT_OF_MEASUREMENT_TEXT_GET'
      EXPORTING
        i_langu = sy-langu
        i_msehi = ls_msehi
      IMPORTING
        e_mseh3 = ls_mein.

    add_bdc_header 'X'    'SAPMV13A'          '0100'.
    add_bdc_body 'BDC_CURSOR'        'RV13A-KSCHL'.
    add_bdc_body 'BDC_OKCODE'        '/00'.
    add_bdc_body 'RV13A-KSCHL'       'ZPRL'.

    add_bdc_header 'X'    'SAPLV14A'          '0100'.
    add_bdc_body 'BDC_OKCODE'        '=WEIT'.
    add_bdc_body 'BDC_CURSOR'        'RV130-SELKZ(02)'.
    add_bdc_body 'RV130-SELKZ(02)'   'X'.

    add_bdc_header 'X'    'SAPMV13A'            '1913'.
    add_bdc_body 'BDC_OKCODE'          '=PDAT'.
    add_bdc_body 'BDC_CURSOR'          'RV13A-DATBI(01)'.
    add_bdc_body 'KOMG-PLTYP'          ls_request-pltyp.
    add_bdc_body 'KOMG-MATNR(01)'      vl_saida.
    add_bdc_body    'KONP-KBETR(01)'      ls_item-kbetr.
    add_bdc_body    'KONP-KONWA(01)'      ls_item-konwa.
    add_bdc_body    'KONP-KMEIN(01)'      ls_mein.
    add_bdc_body    'RV13A-KRECH(01)'     ls_item-krech.
    add_bdc_body    'RV13A-DATAB(01)'     ls_datab.
    add_bdc_body    'RV13A-DATBI(01)'     ls_datbi.

    add_bdc_header 'X'    'SAPMV13A'            '0300'.
    add_bdc_body    'BDC_OKCODE'          '/00'.
    add_bdc_body    'BDC_CURSOR'          'KONP-GKWRT'.
    add_bdc_body    'KONP-KBETR'          ls_item-kbetr.
    add_bdc_body    'KONP-MXWRT'          ls_item-mxwrt.
    add_bdc_body    'KONP-GKWRT'          ls_item-gkwrt.

    add_bdc_header 'X'    'SAPMV13A'            '0300'.
    add_bdc_body    'BDC_OKCODE'          '=SICH'.
    add_bdc_body    'BDC_CURSOR'          'KONP-KBETR'.

    REFRESH it_msg.

    CALL TRANSACTION 'VK11'
      USING it_bdcdata
      MODE 'N'
      UPDATE 'S'
      MESSAGES INTO it_msg.

    " ── Verifica se a BDC realmente gravou o registro ──────────────────────
    CLEAR lv_ok.
    READ TABLE it_msg TRANSPORTING NO FIELDS WITH KEY msgtyp = 'E'.
    IF sy-subrc <> 0.
      READ TABLE it_msg TRANSPORTING NO FIELDS WITH KEY msgtyp = 'A'.
      IF sy-subrc <> 0.
        lv_ok = abap_true.
      ENDIF.
    ENDIF.

    IF lv_ok = abap_false.
      DATA: lv_erro TYPE string,
            lv_txt  TYPE string.
      CLEAR lv_erro.
      LOOP AT it_msg INTO DATA(ls_msg) WHERE msgtyp CA 'EA'.
        CLEAR lv_txt.
        MESSAGE ID ls_msg-msgid TYPE ls_msg-msgtyp NUMBER ls_msg-msgnr
          WITH ls_msg-msgv1 ls_msg-msgv2 ls_msg-msgv3 ls_msg-msgv4
          INTO lv_txt.
        IF lv_erro IS INITIAL.
          lv_erro = lv_txt.
        ELSE.
          lv_erro = |{ lv_erro } / { lv_txt }|.
        ENDIF.
      ENDLOOP.
      IF lv_erro IS INITIAL.
        lv_erro = 'Falha desconhecida ao gravar VK11 (BDC não confirmou a gravação).'.
      ENDIF.

      " Usa ls_item-matnr (como veio no JSON, sem zeros à esquerda) e não
      " vl_saida (convertido por CONVERSION_EXIT_ALPHA_INPUT) — o Pole Price
      " casa a falha pelo product_id sem zeros, então reportar vl_saida aqui
      " fazia a falha nunca ser encontrada do lado do app (sap_erro nunca
      " era gravado, e o material não aparecia para reprocessar).
      APPEND VALUE #( matnr = ls_item-matnr erro = lv_erro ) TO it_falhas.
      CONTINUE. " não tenta bloqueio/exclusão de vigência anterior se a gravação principal falhou
    ENDIF.

    IF ls_item-status NE 'L'.

      IF vl_bloq EQ 'X' OR ls_item-status EQ 'X'.

        CLEAR it_bdcdata.

        add_bdc_header 'X'    'SAPMV13A'          '0100'.
        add_bdc_body    'BDC_CURSOR'        'RV13A-KSCHL'.
        add_bdc_body    'BDC_OKCODE'        '/00'.
        add_bdc_body    'RV13A-KSCHL'       'ZPRL'.

        add_bdc_header    'X'    'SAPLV14A'          '0100'.
        add_bdc_body    'BDC_CURSOR'        'RV130-SELKZ(02)'.
        add_bdc_body    'BDC_OKCODE'        '=WEIT'.
        add_bdc_body    'RV130-SELKZ(02)'   'X'.

        add_bdc_header    'X'    'RV13A913'            '1000'.
        add_bdc_body    'BDC_OKCODE'          '=ONLI'.
        add_bdc_body    'BDC_CURSOR'          'F001'.
        add_bdc_body    'F001'                ls_request-pltyp.
        add_bdc_body    'F002-LOW'            vl_saida.
        add_bdc_body    'SEL_DATE'            ls_datab.

        add_bdc_header    'X'    'SAPMV13A'            '1913'.
        add_bdc_body    'BDC_OKCODE'          '=ENTF'.
        add_bdc_body    'BDC_CURSOR'          'KOMG-MATNR(01)'.
        add_bdc_body    'RV130-SELKZ(01)'     'X'.

        add_bdc_header     'X'    'SAPMV13A'            '1913'.
        add_bdc_body    'BDC_OKCODE'          '=SICH'.
        add_bdc_body    'BDC_CURSOR'          'KOMG-MATNR(01)'.

        REFRESH it_msg.

        CALL TRANSACTION 'VK12'
          USING it_bdcdata
          MODE 'N'
          UPDATE 'S'
          MESSAGES INTO it_msg.

        READ TABLE it_msg TRANSPORTING NO FIELDS WITH KEY msgtyp = 'E'.
        IF sy-subrc = 0.
          APPEND VALUE #( matnr = ls_item-matnr
                           erro  = 'Falha ao bloquear/excluir vigência anterior (VK12).' )
            TO it_falhas.
        ENDIF.

      ENDIF.

    ENDIF.

  ENDLOOP.

  " ── Monta resposta JSON, incluindo eventuais falhas por material ─────────
  DATA(lo_entity) = mo_response->create_entity( ).
  lo_entity->set_content_type( if_rest_media_type=>gc_appl_json ).

  DATA: lv_resp        TYPE string,
        lv_falhas_json TYPE string,
        lv_matnr_json  TYPE string,
        lv_erro_json   TYPE string,
        lv_item_json   TYPE string.

  IF it_falhas IS INITIAL.
    lv_resp = '{"ok":true,"falhas":[]}'.
  ELSE.
    CLEAR lv_falhas_json.
    LOOP AT it_falhas INTO DATA(ls_falha).
      lv_matnr_json = ls_falha-matnr.
      REPLACE ALL OCCURRENCES OF '"' IN lv_matnr_json WITH '\"'.
      lv_erro_json = ls_falha-erro.
      REPLACE ALL OCCURRENCES OF '"' IN lv_erro_json WITH '\"'.

      lv_item_json = |\{"matnr":"{ lv_matnr_json }","erro":"{ lv_erro_json }"\}|.

      IF lv_falhas_json IS INITIAL.
        lv_falhas_json = lv_item_json.
      ELSE.
        lv_falhas_json = |{ lv_falhas_json },{ lv_item_json }|.
      ENDIF.
    ENDLOOP.

    lv_resp = |\{"ok":false,"falhas":[{ lv_falhas_json }]\}|.
  ENDIF.

  lo_entity->set_string_data( lv_resp ).
  mo_response->set_status( 200 ).

ENDMETHOD.
