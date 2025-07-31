/*
** ----------------------------------------------------------------------
** The package customer_tool collects some usefull things working with
** customer stuff.
** ----------------------------------------------------------------------
*/

SET DEFINE OFF

PROMPT ------------------------------------------------------------------;
PROMPT $Id$
PROMPT ------------------------------------------------------------------;

exec registration.register ( -
    registration.package_body, -
    upper ('customer_tool'), -
    '$Id$');


CREATE OR REPLACE PACKAGE BODY customer_tool
AS
    -- $Id$

    v_len_of_vndl                                        BINARY_INTEGER;
    dekosis_dummy_vndl                          CONSTANT CHAR(4) := '9898';


    FUNCTION account_compound_key_get(
        p_account      IN ACCOUNTS%ROWTYPE)
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN format.compound_key(p_account.ACCOUNT_NO, p_account.ACCOUNT_TYPE);
    END account_compound_key_get;


    /*
     * Split account number into branch-id and account number. Length of
     * branch-id is retrieved from parameter LEN_OF_VNDL. The part of the
     * number to be returned is identified by these constants.
     */
    FUNCTION split_account_no(
        p_account_no    IN ACCOUNTS.ACCOUNT_NO%TYPE,
        p_part          IN BINARY_INTEGER)
    RETURN VARCHAR2
    IS
    BEGIN
        CASE p_part
            WHEN customer_tool.account_branch
            THEN RETURN SUBSTR(p_account_no, 1, v_len_of_vndl);

            WHEN customer_tool.account_no
            THEN RETURN RTRIM(SUBSTR(p_account_no, v_len_of_vndl + 1));
        END CASE;
    END split_account_no;


    PROCEDURE set_default_cacc(
        p_cash_account_no      CASH_ACCOUNTS.CASH_ACCOUNT_NO%TYPE
       ,p_currency             usertype.currency
       ,p_customer_id          usertype.customer_no)
    IS
    BEGIN
        UPDATE CUSTOMERS
        SET CASH_ACCOUNT_NO = p_cash_account_no
           ,CACC_CURR       = p_currency
         WHERE CUSTOMER_NO = p_customer_id;
    END;

    /*
    ** get the right price_usage_indicator for a customer
    */
    FUNCTION get_price_usage_indicator(
        p_customer_no       CUSTOMERS.CUSTOMER_NO%TYPE
       ,p_deal_type         ORDR.DEAL_TYPE%TYPE
       ,p_gateway           GATEWAY.GATEWAY%TYPE
       ,p_account_vndl      VARCHAR2
       ,p_account_no        usertype.ACCOUNT_NO
       ,p_wkn               usertype.WKN
       ,p_exch_key          usertype.EXCH_KEY
       ,p_trading_place     MARKET.TRADING_PLACE%TYPE := NULL
       ,p_equity_base_type  VARCHAR2
       ,p_kursbezug         VARCHAR2)
    RETURN VARCHAR2
    IS
        v_usage_indicator    VARCHAR2(16);
        v_sonderheit_sep     VARCHAR2(255);
        crs_sonderheit       usertype.REF_CURSOR;
        v_fee_data_sep       VARCHAR2(255);
        crs_all_fee_data     usertype.REF_CURSOR;
        v_sonderheit         CHAR(1);
        v_kursbezug          CHAR(1);
        v_invoice            INVOICE%ROWTYPE;
    BEGIN
        IF p_kursbezug IS NULL
        THEN
            v_invoice.CUSTOMER_NO          := p_customer_no;
            v_invoice.GATEWAY              := p_gateway;
            v_invoice.ACCOUNT_NO           := p_account_vndl || p_account_no;
            v_invoice.WKN                  := p_wkn;
            v_invoice.BUY_SELL             := order_tool.map_deal_type_to_buy_sell(p_deal_type);
            v_invoice.DEAL_TYPE            := p_deal_type;
            v_invoice.EXCH_KEY             := p_exch_key;
            v_invoice.TRADING_PLACE        := p_trading_place;
            v_invoice.EQUITY_BASE_TYPE     := p_equity_base_type;
            v_invoice.AVERAGE_PRICE        := 1;
            v_invoice.TRADED_CURR          := 'EUR';

            sp_rib_fee_request(
                p_fee_type           => invoice_fees.kursbezug
               ,p_invoice            => v_invoice
               ,p_constellation      => NULL
               ,p_equity             => NULL
               ,p_cust_total_value   => 1
               ,p_cust_total_nominal => 1
               ,p_cp_total_value     => 1
               ,p_cp_total_nominal   => 1
               ,p_order_nominal      => 1
               ,p_sonderheit_sep     => v_sonderheit_sep
               ,p_sonderheit         => crs_sonderheit
               ,p_fee_data_sep       => v_fee_data_sep
               ,p_fee_data           => crs_all_fee_data);

            FETCH crs_sonderheit
            INTO  v_sonderheit,
                  v_kursbezug;

            CLOSE crs_sonderheit;
            CLOSE crs_all_fee_data;
        ELSE
            v_kursbezug := p_kursbezug;
        END IF;

        --
        -- If no indicator is returned default to B, WP
        -- depending on buy/sell indicator.
        --
        IF RTRIM(v_kursbezug) IS NULL OR v_kursbezug = '-' -- '-' from overloaded signature below.
        THEN
            IF v_invoice.BUY_SELL = order_tool.buy
            THEN RETURN 'B';
            ELSE RETURN 'WP';
            END IF;

        -- Explicitely IP.
        ELSIF v_kursbezug = 'A'
        THEN RETURN 'IP';

        -- Explicitely WP.
        ELSIF v_kursbezug = 'R'
        THEN
            IF v_invoice.BUY_SELL = order_tool.buy
            THEN RETURN 'NAV';
            ELSE RETURN 'WP';
            END IF;

        -- Buying Rate
        ELSIF v_kursbezug = 'B'
        THEN RETURN v_kursbezug;

        -- NAV is the only remaining indicator.
        ELSE RETURN 'NAV';

        END IF;
    END get_price_usage_indicator;

    FUNCTION get_price_usage_indicator(p_customer_no       CUSTOMERS.CUSTOMER_NO%TYPE
                                      ,p_deal_type         ORDR.DEAL_TYPE%TYPE
                                      ,p_gateway           GATEWAY.GATEWAY%TYPE
                                      ,p_kursbezug         VARCHAR2) -- from Dekosis
    RETURN VARCHAR2
    IS
    BEGIN
        --
        -- Attribute kursbezug is optional in holeDepotKontoGebuehren_out message.
        -- Use default '-' to avoid a renewed RIBFeeReq request.
        --
        RETURN get_price_usage_indicator(
                   p_customer_no      => p_customer_no,
                   p_deal_type        => p_deal_type,
                   p_gateway          => p_gateway,
                   p_account_vndl     => NULL,
                   p_account_no       => NULL,
                   p_wkn              => NULL,
                   p_exch_key         => NULL,
                   p_equity_base_type => NULL,
                   p_kursbezug        => NVL(p_kursbezug, '-'));
    END;

    FUNCTION get_price_usage_indicator(p_customer_no       CUSTOMERS.CUSTOMER_NO%TYPE
                                      ,p_deal_type         ORDR.DEAL_TYPE%TYPE
                                      ,p_gateway           GATEWAY.GATEWAY%TYPE
                                      ,p_account_vndl      VARCHAR2
                                      ,p_account_no        usertype.ACCOUNT_NO
                                      ,p_wkn               usertype.WKN
                                      ,p_exch_key          usertype.EXCH_KEY
                                      ,p_trading_place     MARKET.TRADING_PLACE%TYPE
                                      ,p_equity_base_type  VARCHAR2)
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN get_price_usage_indicator(
                   p_customer_no      => p_customer_no,
                   p_deal_type        => p_deal_type,
                   p_gateway          => p_gateway,
                   p_account_vndl     => p_account_vndl,
                   p_account_no       => p_account_no,
                   p_wkn              => p_wkn,
                   p_exch_key         => p_exch_key,
                   p_trading_place    => p_trading_place,
                   p_equity_base_type => p_equity_base_type,
                   p_kursbezug        => NULL);
    END;


    --
    -- This procedure sets the user and cost center that is to be sent with
    -- holeDepotKontodaten. If user is null on request PARM(DEF_USER) is taken
    -- as default, if cost center is null PARM(DEF_COST_CTR) will be used.
    -- The procedure should be called before initiaiting the very first request
    -- within an existing session.
    --
    -- The cost center is identified by the parameter p_cost_center or
    -- the associated trading place.
    --
    -- If one of the parameters is passed as NULL an eventually previously set
    -- value will be kept.
    --
    PROCEDURE set_cost_center(
        p_ext_user_id   IN      ORDR_IF.EXT_USER_ID%TYPE  := NULL,
        p_trading_place IN      MARKET.TRADING_PLACE%TYPE := NULL,
        p_cost_center   IN      ORDR_IF.COST_CENTER%TYPE  := NULL)
    IS
        v_market                MARKET%ROWTYPE;
        v_account_data_req      ACCOUNT_DATA_REQ_TMP%ROWTYPE;
        v_cost_center           ACCOUNT_DATA_REQ_TMP.COST_CENTER%TYPE;
    BEGIN
        IF p_cost_center IS NOT NULL THEN
            v_cost_center := p_cost_center;
        ELSE
            sp_market_select(
                p_market_trading_place      => p_trading_place,
                p_market                    => v_market,
                p_strict                    => FALSE);

            v_cost_center := v_market.COST_CENTER;
        END IF;

        BEGIN
            SELECT *
            INTO   v_account_data_req
            FROM   ACCOUNT_DATA_REQ_TMP;

            RETURN;

        EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
                NULL;
        END;

        DELETE FROM ACCOUNT_DATA_REQ_TMP;

        INSERT INTO ACCOUNT_DATA_REQ_TMP(
            EXT_USER_ID,
            COST_CENTER)
        VALUES (
            NVL(p_ext_user_id, v_account_data_req.EXT_USER_ID),
            NVL(v_cost_center, v_account_data_req.COST_CENTER));

        EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
                error.log_message(
                    'customer_tool.set_cost_center',
                    SQLERRM,
                    error.severity_error);
    END set_cost_center;


/*
 * ----------------------------------------------------------------------
 * private procedures/functions for 'holeDepotKontodaten'
 * ----------------------------------------------------------------------
 */

    /*
    ** This procedure performs an RIB access, if the account doesn't exist
    ** in the cache or the data is outdated. The output parameter p_adc_value
    ** returns the value of a given XPath expression.
    */
    PROCEDURE check_account_data_cache(
        p_account_no     IN             usertype.ACCOUNT_NO,
        p_xpath          IN             VARCHAR2 := NULL,
        p_adc_exists        OUT         usertype.YESNO,
        p_adc_is_active     OUT         usertype.YESNO,
        p_adc_value         OUT         VARCHAR2,
        p_xmldata        IN OUT NOCOPY  XMLTYPE)
    IS
      v_counter                         INTEGER := 0;
      v_sysdate                         DATE    := SYSDATE;
      v_ttl_acct                        NUMBER;
      v_load_date                       DATE;
      v_xml_fragment                    XMLTYPE;
    BEGIN
        /*
         * No RIB access for accounts with VNDL 9898
         */
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl
        THEN
            p_adc_is_active := 'N';
            p_adc_exists    := 'N';
            p_adc_value     := NULL;
            RETURN;
        END IF;

        /*
         * If XML data is passed in extract value from there.
         */
        IF p_xmldata IS NOT NULL
        THEN
            v_xml_fragment  := p_xmldata.extract(p_xpath);

            IF v_xml_fragment IS NOT NULL
            THEN
                /*
                 * Extract element text.
                 * Please note that v_xml_fragment.getStringVal will not decode
                 * XML special characters like &amp;.
                 * [#250199738]
                 */
                SELECT extractValue(v_xml_fragment, '//text()')
                INTO   p_adc_value
                FROM   DUAL;

            ELSE p_adc_value := ' ';
            END IF;

            p_adc_is_active := 'Y';
            p_adc_exists    := 'Y';
            RETURN;
        END IF;

        v_ttl_acct := TO_NUMBER(TRIM(parameter_tool.get_parameter_value('TTL_ACCT')));

        LOOP
            BEGIN
                IF p_xpath IS NULL
                THEN
                    SELECT LOAD_DATE,
                           IS_ACTIVE,
                           'Y'
                      INTO v_load_date,
                           p_adc_is_active,
                           p_adc_exists
                      FROM ACCOUNT_DATA_CACHE
                     WHERE ACCOUNT_NO = p_account_no;

                     p_xmldata   := NULL;
                     p_adc_value := NULL;
                ELSE
                    SELECT LOAD_DATE,
                           IS_ACTIVE,
                           'Y',
                           ACCOUNT_DATA
                      INTO v_load_date,
                           p_adc_is_active,
                           p_adc_exists,
                           p_xmldata
                      FROM ACCOUNT_DATA_CACHE
                     WHERE ACCOUNT_NO = p_account_no;

                     v_xml_fragment := p_xmldata.extract(p_xpath);

                     IF v_xml_fragment IS NOT NULL
                     THEN
                        /*
                         * Extract element text.
                         * Please note that v_xml_fragment.getStringVal will not decode
                         * XML special characters like &amp;.
                         * [#250199738]
                         */
                         SELECT extractValue(v_xml_fragment, '//text()')
                         INTO   p_adc_value
                         FROM   DUAL;

                     ELSE p_adc_value := ' ';
                     END IF;
                END IF;

            EXCEPTION
                WHEN NO_DATA_FOUND
                THEN
                    v_load_date     := NULL;
                    p_adc_is_active := 'N';
                    p_adc_exists    := 'N';
                    p_adc_value     := NULL;
                    p_xmldata       := NULL;
            END;

            /*
             * Check, if record is expired
             */
            IF (p_adc_exists = 'Y') AND
               (v_load_date + 1/(24*60) * v_ttl_acct) - v_sysdate >= 0
            THEN EXIT;  -- Not expired!
            ELSE p_adc_is_active := 'N';
            END IF;

            EXIT WHEN v_counter > 0;

            /*
             * Emergency mode, do not try to request data from RIB.
             */
            EXIT WHEN parameter_tool.get_parameter_value('EMGCYMODE') = 'Y';

            DECLARE
                v_ext_user_id   ORDR_IF.EXT_USER_ID%TYPE;
                v_cost_center   MARKET.COST_CENTER%TYPE;
            BEGIN
                BEGIN
                    SELECT EXT_USER_ID,
                           COST_CENTER
                    INTO   v_ext_user_id,
                           v_cost_center
                    FROM   ACCOUNT_DATA_REQ_TMP;

                EXCEPTION
                    WHEN NO_DATA_FOUND
                    THEN NULL;
                END;

                rib_mgr.request(
                    p_function  => 'RIBAcctReq',
                    p_selector1 => 'Qry.Acct='       || RTRIM(p_account_no),
                    p_selector2 => 'Qry.CostCenter=' || NVL(v_cost_center, parameter_tool.get_parameter_value('DEF_COST_CTR')),
                    p_selector3 => 'Qry.UserID='     || NVL(
                                                            v_ext_user_id,                                              -- 1. User set externally
                                                            RTRIM(
                                                                NVL(
                                                                    usersession.get_user,                               -- 2. Session user
                                                                    parameter_tool.get_parameter_value('DEF_USER')      -- 3. Default user
                                                                )
                                                            )
                                                        )
                );

            EXCEPTION
                WHEN rib_mgr.RIB_UNAVAILABLE
                THEN
                    error.log_message(
                        'check_account_data_cache',
                        'RIB was unavailable when requesting data for account ' || RTRIM(p_account_no),
                        error.severity_error);
                    EXIT;

                WHEN rib_mgr.RIB_ACCESS_ERROR
                THEN
                    error.log_message(
                        'check_account_data_cache',
                        'Error while accessing RIB when requesting data for account ' || RTRIM(p_account_no),
                        error.severity_error);
                    EXIT;

                WHEN rib_mgr.APPLICATION_ERROR
                THEN
                    error.log_message(
                        'check_account_data_cache',
                        'General application error when requesting RIB data for account ' || RTRIM(p_account_no),
                        error.severity_error);
                    EXIT;

                WHEN NO_DATA_FOUND
                THEN
                    EXIT;
            END;

            v_counter := v_counter + 1;
        END LOOP;
    END check_account_data_cache;


    PROCEDURE check_account_data_cache(
        p_account_no     IN     usertype.ACCOUNT_NO,
        p_adc_exists        OUT usertype.YESNO,
        p_adc_is_active     OUT usertype.YESNO)
    IS
        v_result                VARCHAR2(255);
        v_xmldata               XMLTYPE;
    BEGIN
        check_account_data_cache(
            p_account_no    => p_account_no,
            p_xpath         => NULL,
            p_adc_exists    => p_adc_exists,
            p_adc_is_active => p_adc_is_active,
            p_adc_value     => v_result,
            p_xmldata       => v_xmldata);
    END check_account_data_cache;


    /*
     * This function extracts one value identified by an XPath expression
     * from the account data cache for the given ACCOUNT_NO.
     */
    FUNCTION extractByXPath(
        p_account_no     IN             usertype.ACCOUNT_NO,
        p_xpath          IN             VARCHAR2,
        p_xmldata        IN OUT NOCOPY  XMLTYPE)
    RETURN VARCHAR2
    IS
        v_adc_exists        usertype.YESNO;
        v_adc_is_active     usertype.YESNO;
        v_result            VARCHAR2(255);
    BEGIN
        IF p_account_no IS NULL
        THEN RETURN NULL;
        ELSE
            check_account_data_cache(
                p_account_no    => p_account_no,
                p_xpath         => p_xpath,
                p_adc_exists    => v_adc_exists,
                p_adc_is_active => v_adc_is_active,
                p_adc_value     => v_result,
                p_xmldata       => p_xmldata);

            RETURN v_result;
        END IF;
    END extractByXPath;


    /*
     * ----------------------------------------------------------------------
     * public procedures/functions for 'holeDepotKontodaten'
     * ----------------------------------------------------------------------
     */

    /*
    ** Check if DEKOSIS dummy account
    */
    FUNCTION is_dekosis_dummy_account(
        p_account_no    IN      usertype.ACCOUNT_NO)
    RETURN BOOLEAN
    IS
    BEGIN
        RETURN split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl;
    END;


    /*
    ** Checks the existence of an (active) ACCOUNT.
    */
    FUNCTION account_exists(
        p_account_no    IN      usertype.ACCOUNT_NO,
        p_check_active  IN      usertype.YESNO := 'N')
    RETURN BOOLEAN
    IS
        v_adc_exists        usertype.YESNO;
        v_adc_is_active     usertype.YESNO;
    BEGIN
        IF p_account_no IS NULL
        THEN RETURN TRUE;
        END IF;

        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            RETURN sp_account_exists(
                       p_account_no   => p_account_no,
                       p_account_type => NULL,
                       p_check_active => p_check_active);
        END IF;

        check_account_data_cache(
            p_account_no    => p_account_no,
            p_adc_exists    => v_adc_exists,
            p_adc_is_active => v_adc_is_active
        );

        IF p_check_active = 'Y' THEN
            IF v_adc_exists = 'Y' AND v_adc_is_active = 'Y' THEN
                RETURN TRUE;
            ELSE
                RETURN FALSE;
            END IF;
        ELSE
            IF v_adc_exists = 'Y' THEN
                RETURN TRUE;
            ELSE
                RETURN FALSE;
            END IF;
        END IF;
    END account_exists;


    /*
     * Select account data from RIB.
     */
    FUNCTION get_account_from_rib(
        p_account_no    IN      usertype.ACCOUNT_NO,
        p_account       OUT     ACCOUNTS%ROWTYPE)
    RETURN BOOLEAN
    IS
        v_adc_exists        usertype.YESNO;
        v_adc_is_active     usertype.YESNO;
        v_xpath             VARCHAR2(255);
        v_account_name      ACCOUNTS.ACCOUNT_NAME%TYPE;
    BEGIN
        RETURN TRUE;
    END get_account_from_rib;


    /*
     * Get a list of all cash accounts for the given account.
     */
    PROCEDURE get_cash_accounts_from_rib(
        p_account_no    IN      usertype.ACCOUNT_NO,
        p_customer_no   IN      usertype.CUSTOMER_NO := NULL,
        p_cash_account  OUT     usertype.REF_CURSOR)
    IS
        v_account           ACCOUNTS%ROWTYPE;
        v_adc_exists        usertype.YESNO;
        v_adc_is_active     usertype.YESNO;
    BEGIN
        IF p_account_no IS NULL
        THEN
            p_cash_account := format.empty_cursor;
            RETURN;
        END IF;

        check_account_data_cache(
            p_account_no    => p_account_no,
            p_adc_exists    => v_adc_exists,
            p_adc_is_active => v_adc_is_active
        );

        IF v_adc_exists = 'Y'
        THEN
            IF p_customer_no IS NULL
            THEN
                OPEN p_cash_account
                FOR
                    /* Alternate cash accounts.
                     */
                    SELECT extractValue(value(t), '/Buchungskonto/vndl'),
                           extractValue(value(t), '/Buchungskonto/ktoNr'),
                           extractValue(value(t), '/Buchungskonto/kontoWaehrung/waehrung'),
                           NULL                                     AS DISP_CONSTELLATION_ID
                    FROM   ACCOUNT_DATA_CACHE a,
                           TABLE(
                               XMLSEQUENCE(
                                   EXTRACT(a.ACCOUNT_DATA,
                                           '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/Buchungskonto')
                               )
                           ) t
                    WHERE  a.ACCOUNT_NO = p_account_no

                    UNION ALL
                    /* Prio Eins cash account.
                     */
                    SELECT extractValue(VALUE(t), '/PrioEinsKonto/vndl'),
                           extractValue(VALUE(t), '/PrioEinsKonto/ktoNr'),
                           extractValue(VALUE(t), '/PrioEinsKonto/kontoWaehrung/waehrung'),
                           NULL                                     AS DISP_CONSTELLATION_ID
                    FROM   ACCOUNT_DATA_CACHE a,
                           TABLE(
                               XMLSEQUENCE(
                                   EXTRACT(a.ACCOUNT_DATA,
                                           '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/PrioEinsKonto')
                                   )
                           ) t
                    WHERE  a.ACCOUNT_NO = p_account_no;
            ELSE
                OPEN p_cash_account
                FOR
                    SELECT DISTINCT
                           ca.VNDL,
                           ca.CASH_ACCOUNT_NO,
                           ca.CACC_CURR,
                           CASE WHEN co.IS_ACTIVE = 'Y'
                                THEN co.CONSTELLATION_ID
                                ELSE NULL
                           END                                      AS DISP_CONSTELLATION_ID
                    FROM (
                          /* Alternate cash accounts.
                           */
                          SELECT RTRIM(extractValue(value(t), '/Buchungskonto/vndl'))  AS VNDL,
                                 RTRIM(extractValue(value(t), '/Buchungskonto/ktoNr')) AS CASH_ACCOUNT_NO,
                                 RTRIM(extractValue(value(t), '/Buchungskonto/kontoWaehrung/waehrung')) AS CACC_CURR
                          FROM   ACCOUNT_DATA_CACHE a,
                                 TABLE(
                                     XMLSEQUENCE(
                                         EXTRACT(a.ACCOUNT_DATA,
                                                 '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/Buchungskonto')
                                     )
                                 ) t
                          WHERE  a.ACCOUNT_NO = p_account_no

                          UNION ALL
                              /* Prio Eins cash account.
                               */
                              SELECT RTRIM(extractValue(VALUE(t), '/PrioEinsKonto/vndl'))  AS VNDL,
                                     RTRIM(extractValue(VALUE(t), '/PrioEinsKonto/ktoNr')) AS CASH_ACCOUNT_NO,
                                     RTRIM(extractValue(VALUE(t), '/PrioEinsKonto/kontoWaehrung/waehrung')) AS CACC_CURR
                              FROM   ACCOUNT_DATA_CACHE a,
                                     TABLE(
                                         XMLSEQUENCE(
                                             EXTRACT(a.ACCOUNT_DATA,
                                                     '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/PrioEinsKonto')
                                             )
                                     ) t
                          WHERE  a.ACCOUNT_NO = p_account_no

                          UNION ALL
                              /* cash accounts from CASH_ACCOUNTS table.
                               */
                              SELECT split_account_no(
                                         cca.CASH_ACCOUNT_NO,
                                         customer_tool.account_branch
                                     )                                   AS VNDL,
                                     split_account_no(
                                         cca.CASH_ACCOUNT_NO,
                                         customer_tool.account_no
                                     )                                   AS CASH_ACCOUNT_NO,
                                     RTRIM(cca.CACC_CURR)                AS CACC_CURR
                                FROM CUSTOMER_CASH_ACCOUNTS cca
                               WHERE cca.CUSTOMER_NO   = p_customer_no
                         ) ca,

                         (SELECT  split_account_no(
                                      c.CASH_ACCOUNT_NO,
                                      customer_tool.account_branch
                                  )                                      AS VNDL,
                                  split_account_no(
                                      c.CASH_ACCOUNT_NO,
                                      customer_tool.account_no
                                  )                                      AS CASH_ACCOUNT_NO,
                                  RTRIM(c.CACC_CURR)                     AS CACC_CURR,
                                  c.CONSTELLATION_ID                     AS CONSTELLATION_ID,
                                  c.IS_ACTIVE                            AS IS_ACTIVE
                            FROM CONSTELLATION c
                           WHERE CUSTOMER_NO = p_customer_no
                         ) co

                    WHERE co.VNDL            (+) = ca.VNDL
                      AND co.CASH_ACCOUNT_NO (+) = ca.CASH_ACCOUNT_NO
                      AND co.CACC_CURR       (+) = ca.CACC_CURR
                    ORDER BY NVL(DISP_CONSTELLATION_ID, '99'), ca.VNDL, ca.CASH_ACCOUNT_NO;
          END IF;

        ELSIF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl
        THEN
            IF p_customer_no IS NULL
            THEN
                OPEN p_cash_account
                FOR
                    SELECT split_account_no(
                               cca.CASH_ACCOUNT_NO,
                               customer_tool.account_branch
                           )
                          ,split_account_no(
                               cca.CASH_ACCOUNT_NO,
                               customer_tool.account_no
                           )
                          ,cca.CACC_CURR
                          ,CASE WHEN c.IS_ACTIVE = 'Y'
                               THEN c.CONSTELLATION_ID
                               ELSE NULL
                           END                                      AS DISP_CONSTELLATION_ID
                      FROM ACCOUNTS a,
                           CUSTOMER_CASH_ACCOUNTS cca,
                           CONSTELLATION c
                     WHERE a.ACCOUNT_NO          = p_account_no
                       AND cca.CUSTOMER_NO       = a.CUSTOMER_NO
                       AND c.CUSTOMER_NO     (+) = cca.CUSTOMER_NO
                       AND c.CASH_ACCOUNT_NO (+) = cca.CASH_ACCOUNT_NO
                       AND c.CACC_CURR       (+) = cca.CACC_CURR
                       AND a.IS_ACTIVE           = 'Y'
                    ORDER BY NVL(DISP_CONSTELLATION_ID, '99'), c.CASH_ACCOUNT_NO;
            ELSE
                OPEN p_cash_account
                FOR
                    SELECT split_account_no(
                               cca.CASH_ACCOUNT_NO,
                               customer_tool.account_branch
                           )
                          ,split_account_no(
                               cca.CASH_ACCOUNT_NO,
                               customer_tool.account_no
                           )
                          ,cca.CACC_CURR
                          ,CASE WHEN c.IS_ACTIVE = 'Y'
                               THEN c.CONSTELLATION_ID
                               ELSE NULL
                           END                                      AS DISP_CONSTELLATION_ID
                      FROM CUSTOMER_CASH_ACCOUNTS cca,
                           CONSTELLATION c
                     WHERE cca.CUSTOMER_NO       = p_customer_no
                       AND c.CUSTOMER_NO     (+) = cca.CUSTOMER_NO
                       AND c.CASH_ACCOUNT_NO (+) = cca.CASH_ACCOUNT_NO
                       AND c.CACC_CURR       (+) = cca.CACC_CURR
                    ORDER BY NVL(DISP_CONSTELLATION_ID, '99'), c.CASH_ACCOUNT_NO;
            END IF;
        ELSE p_cash_account := format.empty_cursor;
        END IF;
    END get_cash_accounts_from_rib;


    /*
    ** Checks if a given cash account exists for the given account (depot).
    ** cash account must be with vndl = 0000XXXXXX
    */
    FUNCTION cash_account_from_rib_exists(
        p_account_no      IN  usertype.ACCOUNT_NO,
        p_cash_account_no IN  usertype.ACCOUNT_NO)
    RETURN BOOLEAN
    IS
        v_adc_exists        usertype.YESNO;
        v_adc_is_active     usertype.YESNO;
        v_exists            INTEGER;
        v_xpath             VARCHAR2(255);
    BEGIN
        RETURN TRUE;
    END cash_account_from_rib_exists;


    /*
    ** get gs_ermaechtigung,
    ** leer - nicht erteilt aber möglich
    ** 1 - erteilt
    ** 2 - keine GSErmächtigung
    */
    FUNCTION get_gs_ermaechtigung(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN CHAR
    IS
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl
        THEN RETURN '1';
        END IF;

        v_xpath := '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/gSErmaechtigung/text()';
        RETURN extractByXPath(p_account_no, v_xpath, p_xmldata);
    END get_gs_ermaechtigung;

    FUNCTION get_gs_ermaechtigung(
        p_account_no            IN      usertype.ACCOUNT_NO)
    RETURN CHAR
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_gs_ermaechtigung(p_account_no, v_xmldata);
    END get_gs_ermaechtigung;


    /*
     * get_lieferdepot_kz
     * 1 or 2 - ok, else error
     */
    FUNCTION get_lieferdepot_kz(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN CHAR
    IS
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            RETURN '0';
        END IF;

        v_xpath := '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/lieferdepotKz/text()';
        RETURN extractByXPath(p_account_no, v_xpath, p_xmldata);
    END get_lieferdepot_kz;

    FUNCTION get_lieferdepot_kz(
        p_account_no    IN              usertype.ACCOUNT_NO)
    RETURN CHAR
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_lieferdepot_kz(p_account_no, v_xmldata);
    END;

    /*
     * get account name (Bezeichnung)
     */
    FUNCTION get_account_name(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN NULL;
    END get_account_name;


    FUNCTION get_account_name(
        p_customer_no   IN              CUSTOMERS.CUSTOMER_NO%TYPE)
    RETURN CUSTOMERS.NAME_1%TYPE
    IS
        v_customer_name CUSTOMERS.NAME_1%TYPE;
    BEGIN
        SELECT NAME_1
        INTO   v_customer_name
        FROM   CUSTOMERS
        WHERE  CUSTOMER_NO = p_customer_no;

        RETURN SUBSTR(v_customer_name, 1, 50);

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN RETURN NULL;
    END get_account_name;


    FUNCTION get_account_name(
        p_recipient     IN              RECIPIENT%ROWTYPE)
    RETURN RECIPIENT.NAME%TYPE
    IS
    BEGIN
        RETURN p_recipient.NAME;
    END get_account_name;

    /*
     * get account type (Kundenart!)
     */
    FUNCTION get_account_type(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN CHAR
    IS
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            RETURN NULL;
        END IF;

        v_xpath := '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/kundenart/text()';
        RETURN NVL(extractByXPath(p_account_no, v_xpath, p_xmldata), ' ');
    END get_account_type;

    FUNCTION get_account_type(
        p_account_no    IN              usertype.ACCOUNT_NO)
    RETURN CHAR
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_account_type(p_account_no, v_xmldata);
    END;


    /*
     * get account category (Kundentyp)
     */
    FUNCTION get_account_category(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN VARCHAR2
    IS
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            RETURN NULL;
        END IF;

        v_xpath := '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/kategorie/text()';
        RETURN extractByXPath(p_account_no, v_xpath, p_xmldata);
    END get_account_category;

    FUNCTION get_account_category(
        p_account_no    IN              usertype.ACCOUNT_NO)
    RETURN VARCHAR2
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_account_category(p_account_no, v_xmldata);
    END;


    /*
     * Get online accounting indicator (Online-Abrechnungskennzeichen)
     * If attribute is not returned by RIB or if it is empty it defaults
     * to '3'.
     */
    FUNCTION get_online_accounting_ind(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN VARCHAR2
    IS
        v_result                VARCHAR2(255);
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            v_result := 'O'; -- Online
        ELSE
            v_xpath  := '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto/Depot/Meldeinformationen/onlineAbrechnungsKz/text()';
            v_result := extractByXPath(p_account_no, v_xpath, p_xmldata);
        END IF;

        IF RTRIM(v_result) = 'O'                -- Online
        THEN RETURN '1';

        ELSIF RTRIM(v_result) = 'Z'             -- Online ZaSt optimiert
        THEN RETURN '2';

        ELSE RETURN NVL(RTRIM(v_result), '3');  -- Batch
        END IF;
    END get_online_accounting_ind;

    FUNCTION get_online_accounting_ind(
        p_account_no    IN              usertype.ACCOUNT_NO)
    RETURN VARCHAR2
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_online_accounting_ind(p_account_no, v_xmldata);
    END;


    /*
     * Get external customer no
     */
    FUNCTION get_ext_customer_no(
        p_account_no    IN              usertype.ACCOUNT_NO,
        p_xmldata       IN OUT NOCOPY   XMLTYPE)
    RETURN VARCHAR2
    IS
        v_xpath                 VARCHAR2(255);
    BEGIN
        IF split_account_no(p_account_no, customer_tool.account_branch) = dekosis_dummy_vndl THEN
            RETURN '1';
        END IF;

        v_xpath :=   '//holeDepotKontodaten_out/DepotBetreuerLink/DepotKonto'
                   || '[vndl="'  || split_account_no(p_account_no, customer_tool.account_branch) || '"]'
                   || '[ktoNr="' || split_account_no(p_account_no, customer_tool.account_no) || '"]'
                   || '/Kunde/kundenNr/text()';
        RETURN extractByXPath(p_account_no, v_xpath, p_xmldata);
    END get_ext_customer_no;

    FUNCTION get_ext_customer_no(
        p_account_no    IN              usertype.ACCOUNT_NO)
    RETURN VARCHAR2
    IS
        v_xmldata                       XMLTYPE;
    BEGIN
        RETURN get_ext_customer_no(p_account_no, v_xmldata);
    END;

    /*
     * Get fx spread for the given account.
     */
    FUNCTION get_fx_spread(
        p_customer_no           IN      CUSTOMERS.CUSTOMER_NO%TYPE,
        p_account_no            IN      usertype.ACCOUNT_NO,
        p_wkn                   IN      usertype.WKN,
        p_trading_place         IN      MARKET.TRADING_PLACE%TYPE,
        p_equity_base_type      IN      VARCHAR2,
        p_deal_type             IN      ORDR.DEAL_TYPE%TYPE,
        p_exch_key              IN      usertype.EXCH_KEY,
        p_delivery_key          IN      VARCHAR2,
        p_cost_center           IN      MARKET.COST_CENTER%TYPE,
        p_gateway               IN      GATEWAY.GATEWAY%TYPE)
    RETURN CHAR
    IS
        v_sonderheit_sep                VARCHAR2(200);
        v_sonderheit                    CHAR(1);
        v_kursbezug                     CHAR(1);
        c_sonderheit                    usertype.REF_CURSOR;
        v_fee_data_sep                  VARCHAR2(200);
        c_fee_data                      usertype.REF_CURSOR;
        v_invoice                       INVOICE%ROWTYPE;


    BEGIN
        v_invoice.CUSTOMER_NO          := p_customer_no;
        v_invoice.GATEWAY              := p_gateway;
        v_invoice.ACCOUNT_NO           := p_account_no;
        v_invoice.WKN                  := p_wkn;
        v_invoice.BUY_SELL             := order_tool.map_deal_type_to_buy_sell(p_deal_type);
        v_invoice.DEAL_TYPE            := p_deal_type;
        v_invoice.EXCH_KEY             := p_exch_key;
        v_invoice.TRADING_PLACE        := p_trading_place;
        v_invoice.EQUITY_BASE_TYPE     := p_equity_base_type;
        v_invoice.AVERAGE_PRICE        := 1;
        v_invoice.TRADED_CURR          := 'EUR';

        sp_rib_fee_request(
            p_fee_type           => invoice_fees.devisenkonditionen,
            p_invoice            => v_invoice,
            p_constellation      => NULL,
            p_equity             => NULL,
            p_cust_total_value   => 1,
            p_cust_total_nominal => 1,
            p_cp_total_value     => 1,
            p_cp_total_nominal   => 1,
            p_order_nominal      => 1,
            p_sonderheit_sep     => v_sonderheit_sep,
            p_sonderheit         => c_sonderheit,
            p_fee_data_sep       => v_fee_data_sep,
            p_fee_data           => c_fee_data);

        FETCH c_sonderheit
        INTO  v_sonderheit,
              v_kursbezug;

        IF c_sonderheit%NOTFOUND
        THEN v_sonderheit := NULL;
        END IF;

        CLOSE c_sonderheit;
        CLOSE c_fee_data;

        RETURN v_sonderheit;
    END get_fx_spread;


    /*
    ** get additional custody data via sp_custody_select
    ** for use in SQL statements
    */
    FUNCTION custody_get_add_data(
        p_custody usertype.CUSTODY,
        p_switch  VARCHAR2)
    RETURN VARCHAR2
    IS
       v_custody_row               CUSTODY_T;
    BEGIN
       sp_custody_select(
           p_custody      => p_custody,
           p_delivery_key => '6',
           p_custody_row  => v_custody_row);

       CASE p_switch
          WHEN 'CUSTODY'
          THEN RETURN v_custody_row.CUSTODY;

          WHEN 'COUNTRY'
          THEN RETURN v_custody_row.COUNTRY;

          WHEN 'NAME'
          THEN RETURN v_custody_row.NAME;

          WHEN 'NAME_ADDENDUM'
          THEN RETURN v_custody_row.NAME_ADDENDUM;

          WHEN 'LOCATION'
          THEN RETURN v_custody_row.LOCATION;

          WHEN 'BIC_CODE'
          THEN RETURN v_custody_row.BIC_CODE;

          WHEN 'ROUTING_PATH'
          THEN RETURN v_custody_row.ROUTING_PATH;

          WHEN 'SWIFT_INSTRUCTION_TYPE'
          THEN RETURN v_custody_row.SWIFT_INSTRUCTION_TYPE;

          WHEN 'DEADLINE_DAYS'
          THEN RETURN v_custody_row.DEADLINE_DAYS;

          WHEN 'DEADLINE'
          THEN RETURN v_custody_row.DEADLINE;

          ELSE RETURN NULL;
       END CASE;
    END custody_get_add_data;

    /*
     * Determine WL indicator of INVOICE record.
     */
    PROCEDURE get_wl_indicator(
        p_invoice IN OUT NOCOPY INVOICE%ROWTYPE,
        p_order   IN            ORDR%ROWTYPE := NULL)
    IS
        v_customer CUSTOMERS%ROWTYPE;
    BEGIN
        p_invoice.WHITE_LABEL_INDICATOR := 'N';

        -- Counterparts never get a WL indicator.
        IF p_invoice.TRANSACTION_TYPE = 'C'
        THEN RETURN;
        END IF;

        -- Customer nostro aggregate.
        IF     p_invoice.NOSTRO = 'Y'
           AND p_invoice.AGGREGATION ='Y'

        THEN
        p_invoice.WHITE_LABEL_INDICATOR :='Y';
            RETURN;
        END IF;

        -- mass order customer invoice
        IF     p_invoice.NOSTRO           = 'N'
           AND p_invoice.TRANSACTION_TYPE = 'A'
           AND p_invoice.GATEWAY in ('VKA','INV','WIE','BOR')
        THEN
            p_invoice.WHITE_LABEL_INDICATOR :='Y';
            RETURN;
        END IF;

        -- no WL indicators for internal customer bookings
        IF  p_invoice.NOSTRO = 'Y'
        THEN RETURN;
        END IF;

        -- BEST maintained WL indicators
        IF p_invoice.CUSTOMER_NO IS NOT NULL
        THEN
            sp_customer_select(
                p_customer_no => p_invoice.CUSTOMER_NO,
                p_customer    => v_customer);

            p_invoice.WHITE_LABEL_INDICATOR := v_customer.WHITE_LABEL_INDICATOR;
            RETURN;
        END IF;

        p_invoice.WHITE_LABEL_INDICATOR := 'Y';
    END get_wl_indicator;

    /*
    ** Computation of the risk profile by comparing the customer's and his account's risk profile
    */
    PROCEDURE compute_risk_profile (
        p_risk_profile_customer IN  INTERNAL_CODES.INTERNAL_CODE%TYPE,
        p_risk_profile_account  IN  INTERNAL_CODES.INTERNAL_CODE%TYPE := NULL,
        p_account_no            IN  ACCOUNTS.ACCOUNT_NO%TYPE          := NULL,
        p_owner_type            IN  CHAR                              := NULL,
        p_risk_profile          OUT EXTERNAL_CODES.SHORT_NAME%TYPE)
    IS
        v_risk_profile_customer_ext EXTERNAL_CODES.EXTERNAL_CODE%TYPE;
        v_risk_profile_account_ext  EXTERNAL_CODES.EXTERNAL_CODE%TYPE;
        v_risk_profile_ext          EXTERNAL_CODES.EXTERNAL_CODE%TYPE;
        v_cust_num                  NUMBER;
        v_acc_num                   NUMBER;
        v_owner_of_account          CUSTOMERS.CUSTOMER_NO%TYPE;
        v_person_type               CHAR(1);
        v_ext_attributes            ext_attributes.t_ext_attribute;

        FUNCTION to_bit_vector(p_rl IN INTEGER)
        RETURN BINARY_INTEGER
        IS
        BEGIN
             RETURN
                 CASE
                 WHEN p_rl = 0 THEN 0  -- NONE ALLOWED
                 WHEN p_rl < 4 THEN 1  -- ONLY OPTIONS ALLOWED
                 WHEN p_rl = 4 THEN 3  -- FUTURES AND OPTIONS ALLOWED
                 WHEN p_rl = 5 THEN 2  -- ONLY FUTURES ALLOWED
                               ELSE 3  -- FUTURES AND OPTIONS ALLOWED
                 END;
        END to_bit_vector;
    BEGIN
        -- get external code from customer risk profile (internal code)
        v_risk_profile_customer_ext := describe_tool.get_external_code(
                                           p_internal_code =>  p_risk_profile_customer,
                                           p_grouping      => 'RISK_PROFILE');

        -- default is customer risk profile
        v_risk_profile_ext := v_risk_profile_customer_ext;

        IF p_risk_profile_account IS NOT NULL
        THEN
            -- get external code from account risk profile (internal code)
            v_risk_profile_account_ext := describe_tool.get_external_code(
                                              p_internal_code =>  p_risk_profile_account,
                                              p_grouping      => 'RISK_PROFILE');

        ELSIF NVL(p_owner_type,' ') = 'A' -- 'Authorised'
        THEN
            -- get owner of account
            SELECT co.CUSTOMER_NO
              INTO v_owner_of_account
              FROM CONSTELLATION co
                   INNER JOIN EXT_CONSTELLATION_ATTRIBUTES eco1
                      ON (    eco1.CUSTOMER_NO = co.CUSTOMER_NO
                          AND eco1.CONSTELLATION_ID = co.CONSTELLATION_ID
                          AND eco1.ATTRIBUTE_TYPE = 'CONS_KIM'
                          AND eco1.KEY            = 'OwnerType'
                          AND eco1.VALUE          = 'O')
             WHERE co.ACCOUNT_NO = p_account_no
               AND co.IS_ACTIVE = 'Y';

            -- get person type of owner
             ext_attributes."select"(
                 p_collection         => 'EXT_CUSTOMER_ATTRIBUTES',
                 p_key1               => v_owner_of_account,
                 p_ext_attribute_type => 'CUST_KIM',
                 p_ext_attribute_key  => 'PersonType',
                 p_ext_attribute      => v_ext_attributes
             );
             v_person_type := v_ext_attributes.value;

            -- if owner is a person
            IF NVL(v_person_type,'C') = 'P'
            THEN
                v_risk_profile_account_ext := '0';
            ELSE
                v_risk_profile_account_ext := '4';
            END IF;
        END IF;

        -- if owner type is 'Authorised', account and customer risk profile
        -- must be compared and the minimum must be chosen
        IF NVL(p_owner_type,' ') = 'A'
        THEN
            v_risk_profile_ext := '0';

            v_cust_num := TO_NUMBER(v_risk_profile_customer_ext);
            v_acc_num  := TO_NUMBER(v_risk_profile_account_ext);

            CASE BITAND(to_bit_vector(v_cust_num), to_bit_vector(v_acc_num))
                    WHEN 0 THEN v_risk_profile_ext := '0';
                    WHEN 1 THEN v_risk_profile_ext := LEAST(SUBSTR(v_risk_profile_customer_ext, 1, 1), SUBSTR(v_risk_profile_account_ext, 1, 1));
                    WHEN 2 THEN v_risk_profile_ext := '5';
                    WHEN 3 THEN CASE
                                WHEN v_cust_num = v_acc_num THEN v_risk_profile_ext := v_cust_num;
                                                            ELSE v_risk_profile_ext := LEAST(SUBSTR(v_risk_profile_customer_ext,1,1),
                                                                                         SUBSTR(v_risk_profile_account_ext,1,1))*10;
                                END CASE;
            END CASE;
         END IF;

         -- get the short name of the risk profile (external code)
         p_risk_profile := describe_tool.get_short_name(
                               p_external_code => v_risk_profile_ext,
                               p_grouping      => 'RISK_PROFILE');
    END compute_risk_profile;


    /*
     * Check the given account information and return a list of matching
     * constellations.
     */
    FUNCTION account_check(
        p_customer_id      IN VARCHAR2,
        p_constellation_id IN VARCHAR2,
        p_account_no       IN VARCHAR2)
    RETURN T_CONSTELLATION_PK_TABLE
    IS
        v_found    BOOLEAN := FALSE;
        v_base_set T_CONSTELLATION_PK_TABLE;

        /*********************************************************************
        ** local match functions: provide a base set of matching customer_id /
        ** constellation_id pairs corresponding to actual search criterion
        **********************************************************************
        */

        /*
        ** match_by_pk: customer no and constellation id have to match.
        ** Throws exception if no data found.
        */
        FUNCTION match_by_pk(
            p_customer_id           IN            VARCHAR2,
            p_constellation_id      IN            VARCHAR2,
            p_base_set                 OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                                   T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            FOR v_r IN (
                SELECT CUSTOMER_NO, CONSTELLATION_ID
                FROM   CONSTELLATION
                WHERE  CUSTOMER_NO      = RPAD(p_customer_id, 12, ' ')
                  AND  CONSTELLATION_ID = p_constellation_id
                  AND  IS_ACTIVE = 'Y')
            LOOP
                p_base_set.extend;
                p_base_set(p_base_set.count) :=
                    T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
            END LOOP;

            RETURN (p_base_set.count <> 0);
        END; -- match_by_pk

        /*
        ** match_by_const_id: constellation id and optional account no.
        ** Throws exception if no data found in case of p_strict=TRUE.
        */
        FUNCTION match_by_const_id(
            p_constellation_id    IN         VARCHAR2,
            p_account_no          IN         CONSTELLATION.ACCOUNT_NO%TYPE,
            p_strict              IN         BOOLEAN DEFAULT FALSE,
            p_base_set            OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                              T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            FOR v_r IN (
                SELECT CUSTOMER_NO, CONSTELLATION_ID
                FROM   CONSTELLATION
                WHERE  CONSTELLATION_ID = p_constellation_id
                  AND  ACCOUNT_NO       = NVL(RPAD(p_account_no, 19, ' '), ACCOUNT_NO)
                  AND  IS_ACTIVE = 'Y')
            LOOP
                p_base_set.extend;
                p_base_set(p_base_set.count) :=
                    T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
            END LOOP;

            RETURN (p_base_set.count <> 0);
        END; -- match_by_const_id

        /*
        ** match_by_account: account no and optional customer id.
        ** Throws exception if no data found.
        */
        FUNCTION match_by_account(
            p_account_no          IN         CONSTELLATION.ACCOUNT_NO%TYPE,
            p_customer_id         IN         VARCHAR2,
            p_base_set            OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                              T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            IF feature_tool.has_feature('HOOK_ACCOUNT_CHECK2.MATCH_BY_ACCOUNT')
            THEN
                DECLARE
                    v_feature_data T_FEATURE_DATA := T_FEATURE_DATA();
                    r              PLS_INTEGER;
                BEGIN
                    v_feature_data.vc2_table(1) := LTRIM(p_account_no, '0');
                    v_feature_data.vc2_table(2) := p_customer_id;
                    feature_tool.set_feature_data(v_feature_data);

                    r := feature_tool.execute_feature('HOOK_ACCOUNT_CHECK2.MATCH_BY_ACCOUNT');

                    v_feature_data := TREAT(feature_tool.get_feature_data() AS T_FEATURE_DATA);

                    FOR i IN 1..v_feature_data.dataset.GetCount
                    LOOP
                      r := v_feature_data.dataset.GetInstance;
                      r := v_feature_data.dataset.GetObject(v_r);
                      
                      p_base_set.extend;
                      p_base_set(p_base_set.count) := v_r;
                    END LOOP;
                END;
            ELSE
                FOR v_r IN (
                    SELECT CUSTOMER_NO, CONSTELLATION_ID
                    FROM   CONSTELLATION
                    WHERE  ACCOUNT_NO  = RPAD(p_account_no, 19, ' ')
                      AND  CUSTOMER_NO = NVL(RPAD(p_customer_id, 12, ' '), CUSTOMER_NO)
                      AND  IS_ACTIVE = 'Y')
                LOOP
                    p_base_set.extend;
                    p_base_set(p_base_set.count) :=
                        T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
                END LOOP;
            END IF;

            RETURN (p_base_set.count <> 0);
        END; -- match_by_account

        /*
        ** alt_match_by_pk: searches customer no concatenated with constellation id.
        ** NO EXCEPTION IS THROWN!
        */
        FUNCTION alt_match_by_pk(
            p_customer_id         IN         VARCHAR2,
            p_base_set            OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                              T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            FOR v_r IN (
                SELECT CUSTOMER_NO, CONSTELLATION_ID
                FROM   CONSTELLATION
                WHERE  RTRIM(CUSTOMER_NO) || CONSTELLATION_ID = p_customer_id
                  AND  IS_ACTIVE = 'Y')
            LOOP
                p_base_set.extend;
                p_base_set(p_base_set.count) :=
                    T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
            END LOOP;

            RETURN (p_base_set.count <> 0);
        END; -- alt_match_by_pk

        /*
        ** match_by_const_group: constellation group matches customer id;
        ** account no is optional. NO EXCEPTION IS THROWN!
        */
        FUNCTION match_by_const_group(
            p_customer_id         IN         VARCHAR2,
            p_account_no          IN         CONSTELLATION.ACCOUNT_NO%TYPE,
            p_base_set            OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                              T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            FOR v_r IN (
                SELECT CUSTOMER_NO, CONSTELLATION_ID
                FROM   CONSTELLATION
                WHERE  CONSTELLATION_GROUP = p_customer_id
                  AND  ACCOUNT_NO          = NVL(RPAD(p_account_no, 19, ' '), ACCOUNT_NO)
                  AND  IS_ACTIVE = 'Y')
            LOOP
                p_base_set.extend;
                p_base_set(p_base_set.count) :=
                    T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
            END LOOP;

            RETURN (p_base_set.count <> 0);
        END; -- match_by_const_group

        /*
        ** match_by_customer_no: customer no and optional account no.
        ** NO EXCEPTION IS THROWN!
        */
        FUNCTION match_by_customer_no(
            p_customer_id         IN         VARCHAR2,
            p_account_no          IN         CONSTELLATION.ACCOUNT_NO%TYPE,
            p_base_set            OUT NOCOPY T_CONSTELLATION_PK_TABLE)
        RETURN BOOLEAN
        IS
            v_r                              T_CONSTELLATION_PK_OBJECT;
        BEGIN
            p_base_set := T_CONSTELLATION_PK_TABLE();

            FOR v_r IN (
                SELECT CUSTOMER_NO, CONSTELLATION_ID
                FROM   CONSTELLATION
                WHERE  CUSTOMER_NO = RPAD(p_customer_id, 12, ' ')
                  AND  ACCOUNT_NO  = NVL(RPAD(p_account_no, 19, ' '), ACCOUNT_NO)
                  AND  IS_ACTIVE = 'Y')
            LOOP
                p_base_set.extend;
                p_base_set(p_base_set.count) :=
                    T_CONSTELLATION_PK_OBJECT(v_r.CUSTOMER_NO, v_r.CONSTELLATION_ID);
            END LOOP;

            RETURN (p_base_set.count <> 0);
        END; -- match_by_customer_no

    BEGIN
        /*
        ** Match by PK.
        ** match_by_pk will throw an exception if no data is found.
        */
        IF p_customer_id IS NOT NULL AND p_constellation_id IS NOT NULL
        THEN v_found :=  match_by_pk(p_customer_id, p_constellation_id, v_base_set);
        END IF;

        /*
        ** Match by constellation id and optional account number.
        ** Throws an exception if no data is found.
        */
        IF NOT v_found AND p_constellation_id IS NOT NULL
        THEN
            v_found := match_by_const_id( p_constellation_id, p_account_no, TRUE, v_base_set);
        END IF;

        /*
        ** Match by account and optional customer number.
        ** Throws an exception if no data is found.
        */
        IF NOT v_found AND p_account_no IS NOT NULL
        THEN v_found := match_by_account(p_account_no, p_customer_id, v_base_set);
        END IF;

        /*
        ** From now on different interpretation of p_customer_id must be tested.
        ** The different functions do not throw an exception but if in the end
        ** no data has been found a no data found exception is required anyway,
        */

        -- ambiguous customer id ( = customer_id || constellation_id)
        IF NOT v_found
        THEN v_found := alt_match_by_pk( p_customer_id,  v_base_set);
        END IF;

         -- customer id interpreted as constellation id
        IF NOT v_found
        THEN v_found := match_by_const_id(p_customer_id, p_account_no, FALSE, v_base_set);
        END IF;

        -- ambiguous customer id containing const. group
        IF NOT v_found
        THEN v_found := match_by_const_group(p_customer_id, p_account_no, v_base_set);
        END IF;

        -- ambiguous customer id interpreted as customer no
        IF NOT v_found
        THEN v_found := match_by_customer_no(p_customer_id, p_account_no, v_base_set);
        END IF;

        -- ambiguous customer id interpreted as customer no - padded with zeros on left-side
        IF NOT v_found
        THEN v_found := match_by_customer_no(LPAD(p_customer_id,12,'0'), p_account_no, v_base_set);
        END IF;

        RETURN v_base_set;
    END account_check;

    /*
     * If system supports some kind of shortened account numbers the
     * function returns the normalized representation for those
     * if in existance.
     * E.g.: There may be a domain prefix like DE or ES although
     * account no. itself is already unique. In this case the
     * short form is expanded to the prefixed one.
     */
    FUNCTION normalize_account_no(p_account_no IN VARCHAR2) RETURN VARCHAR2
    IS
        v_constellations T_CONSTELLATION_PK_TABLE;
        v_standard_user  STANDARD_USER%ROWTYPE;
        v_account_no     CONSTELLATION.ACCOUNT_NO%TYPE;
    BEGIN
        v_constellations := customer_tool.account_check(NULL, NULL, p_account_no);

        CASE
            WHEN v_constellations.count = 0
            THEN RETURN p_account_no;

            ELSE
                sp_standard_user_select (
                    p_user_initial  => usersession.get_user,
                    p_strict        => FALSE,
                    p_standard_user => v_standard_user);

                SELECT DISTINCT c.ACCOUNT_NO
                INTO   v_account_no
                FROM        CONSTELLATION c
                       JOIN TABLE(CAST(v_constellations AS T_CONSTELLATION_PK_TABLE)) t
                       ON   (    c.CUSTOMER_NO      = t.CUSTOMER_NO
                             AND c.CONSTELLATION_ID = t.CONSTELLATION_ID)
                       JOIN CUSTOMERS cu
                       ON   (t.CUSTOMER_NO = cu.CUSTOMER_NO)
                WHERE EXISTS (
                   SELECT COLUMN_VALUE
                   FROM   TABLE(CAST(sp_permitted_teams_get(usersession.get_user) AS T_EXT_TEAM_ACCESS_TABLE)) p
                   WHERE  RTRIM (p.COLUMN_VALUE) = NVL (NVL (RTRIM (c.TEAM_NAME), RTRIM (cu.TEAM_NAME)), RTRIM (v_standard_user.TEAM_NAME)))
                ORDER BY 1;
        END CASE;

        RETURN RTRIM(v_account_no);
    END normalize_account_no;


    /*
     * Concatenate name fragments according to the pattern
     *
     * [Salutation ] + [Title ] + Name + [, Given Name]
     *
     * Fragments in brackets are omitted if NULL.
     */
    FUNCTION "concat"(
        p_name_1 IN VARCHAR2,                   -- Name
        p_name_2 IN VARCHAR2 DEFAULT NULL,      -- Given Name
        p_name_3 IN VARCHAR2 DEFAULT NULL,      -- Title
        p_name_4 IN VARCHAR2 DEFAULT NULL)      -- Salutation
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN
               CASE WHEN TRIM(p_name_4) IS NOT NULL THEN TRIM(p_name_4) || ' ' END
            || CASE WHEN TRIM(p_name_3) IS NOT NULL THEN TRIM(p_name_3) || ' ' END
            || TRIM(p_name_1)
            || CASE WHEN TRIM(p_name_2) IS NOT NULL THEN ', ' || TRIM(p_name_2) || ' ' END;
    END;


    /*
     * Standard function for retrieval of customer name.
     * Prio 1 name is taken from constellation, if not
     * found name from customers table is taken instead.
     */
    FUNCTION get_account_holder(
        p_customer_no      IN ORDR.CUSTOMER_NO%TYPE,
        p_constellation_id IN ORDR.CONSTELLATION_ID%TYPE,
        p_account_no       IN ORDR.CUSTOMER_DEPOT_NO%TYPE,
        p_account_type     IN ORDR.CUSTOMER_DEPOT_NO%TYPE 
    )
    RETURN VARCHAR2 RESULT_CACHE DETERMINISTIC
    IS
        c                usertype.REF_CURSOR;
        v_account_holder VARCHAR2(255);
    BEGIN
        OPEN c
        FOR
            SELECT *
            FROM (
                SELECT NAME
                    FROM (
                        SELECT 2 AS PRIO,
                               customer_tool."concat"(c.NAME_1, c.NAME_2) AS NAME
                        FROM   CUSTOMERS c
                        WHERE  c.CUSTOMER_NO       =  p_customer_no
                        UNION ALL
                        SELECT 1 AS PRIO,
                               co.NAME
                        FROM   CONSTELLATION co
                        WHERE  co.CUSTOMER_NO      =  p_customer_no
                           AND co.CONSTELLATION_ID =  p_constellation_id
                )
                ORDER BY PRIO
            );
       
        FETCH c INTO v_account_holder;
        CLOSE c;

        RETURN v_account_holder;
    END;

BEGIN
    v_len_of_vndl := TO_NUMBER(parameter_tool.get_parameter_value('LEN_OF_VNDL'));
END customer_tool;
/

SHOW ERRORS
EXIT
