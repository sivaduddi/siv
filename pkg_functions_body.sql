/* ===========================================================================
** (c) IBM - e-Financial Solutions,   ALL RIGHTS RESERVED
** ---------------------------------------------------------------------------
** Project:         Consors FutureTrader
** Script:          cft_order_val_check_functions_body.sql
** Description:     create package body for package cft_order_val_check_functions.
**                  this package contains all subfunctions called by
**                  sp_order_validate
** ---------------------------------------------------------------------------
** $Id$
** ===========================================================================
*/

PROMPT ------------------------------------------------------------------;
PROMPT $Id$
PROMPT ------------------------------------------------------------------;

CREATE OR REPLACE PACKAGE BODY cft_order_val_check_functions
AS
    -- $Id$

    /*
    ** Checks if client channel is set
    ** sp_bt_order_channel_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0010(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
        p_check_cond_met := 'N';

        IF (    order_val_check_functions.v_validation_data IS NULL
            OR  order_val_check_functions.v_validation_data.CLIENT_CHANNEL IS NULL)
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40010),
                p_check_cond_met => p_check_cond_met);
        END IF;

    END sp_order_val_check_0010;



    /*
    ** Checks if today or the expiry date is a holiday
    ** sp_fo_cntr_today_holi_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0020(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_trading_day_today    DATE;
        v_trading_day_expiry   DATE;

        v_wkn                  CHAR(12);
        v_exch_key             CHAR(12);
    BEGIN
        p_check_cond_met := 'N';
        v_wkn            := order_val_check_functions.v_validation_data.WKN;
        v_exch_key       := order_val_check_functions.v_validation_data.EXCH_KEY;

        v_trading_day_today := sp_rib_date_add_with_holidays(
            p_date     => TRUNC(SYSDATE),
            p_offset   => 0,
            p_wkn      => v_wkn,
            p_exch_key => v_exch_key);

        IF    v_trading_day_today IS NULL
           OR TRUNC(v_trading_day_today) <> TRUNC(SYSDATE)
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40020),
                p_check_cond_met => p_check_cond_met);
        END IF;

        -- if GTC there is no expiry date => only the date of order capture is of interest
        IF ( order_val_check_functions.v_validation_data.TRADING_RESTR_CODE <> 'GTC')
        THEN
            v_trading_day_expiry := sp_rib_date_add_with_holidays(
                p_date    => TRUNC(order_val_check_functions.v_validation_data.EXPIRY),
                p_offset => 0,
                p_wkn      => v_wkn,
                p_exch_key => v_exch_key);

            IF    v_trading_day_expiry IS NULL
               OR TRUNC(v_trading_day_expiry) <>
                  TRUNC(order_val_check_functions.v_validation_data.EXPIRY)
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40021),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    END sp_order_val_check_0020;


    /*
    ** Number of contracts must be greater than zero
    ** sp_fo_quantity_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0030(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
        p_check_cond_met := 'N';

        IF order_val_check_functions.v_validation_data.QUANTITY <= 0
        THEN
            -- Number of contracts of an OAO closing order can be zero
            IF     order_val_check_functions.v_validation_data.WORKING_ORDER_REC.COLLECTIVE_ORDER_TYPE = 'OAO'
               AND order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'C'
               AND order_val_check_functions.v_validation_data.QUANTITY = 0
            THEN
                NULL;
            ELSE
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40030),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    END sp_order_val_check_0030;



    /*
    ** Checks, if contract is allowed for a risk profile and the number of contracts fits
    ** sp_bt_cntr_risk_lvl_rest_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0040(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_accounts_rec                    T_ACCOUNTS_OBJECT;
        v_customer                        CUSTOMERS%ROWTYPE;
        v_owner_type                      CHAR(1);
        v_risk_profile                    CHAR(12);
    BEGIN
        p_check_cond_met := 'N';

        IF ( order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'O')
        THEN

            -- getting customer
            sp_customer_select(order_val_check_functions.v_validation_data.CUSTOMER_NO, v_customer);

            -- getting account
            v_accounts_rec := order_val_check_functions.v_validation_data.ACCOUNTS_REC;

            -- determining owner type (Owner, Co-owner, Authorised, Asset manager)
            SELECT DISTINCT c.VALUE
            INTO v_owner_type
            FROM EXT_CONSTELLATION_ATTRIBUTES c
            WHERE c.CUSTOMER_NO    = order_val_check_functions.v_validation_data.CUSTOMER_NO
            AND c.CONSTELLATION_ID = order_val_check_functions.v_validation_data.SYS_CONSTELLATION_ID
            AND c.ATTRIBUTE_TYPE   = 'CONS_KIM'
            AND c.KEY              = 'OwnerType';

            -- determining risk profile
            customer_tool.compute_risk_profile (
                p_risk_profile_customer => v_customer.CUSTOMER_RISKPROFILE,
                p_risk_profile_account  => TO_NUMBER(v_accounts_rec.RISK_PROFILE),
                p_account_no            => v_accounts_rec.ACCOUNT_NO,
                p_owner_type            => v_owner_type,
                p_risk_profile          => v_risk_profile
            );

            IF NVL(check_risk_profile(p_validation, p_check_cond_met, v_risk_profile), FALSE)
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40040),
                    p_check_cond_met => p_check_cond_met);
            END IF;


        END IF;
    END sp_order_val_check_0040;



    /*
    ** Checks, if the customer has long and short positions within the same contract
    ** sp_bt_closing_allowed_test
    ** soft check and failure reaction 'REJECTED'
    */
    PROCEDURE sp_order_val_check_0050(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        TYPE t_contract_key_list IS TABLE OF NUMBER(38) INDEX BY BINARY_INTEGER;

        v_position                        T_CFT_POSITION;
        v_current_position                T_CFT_POSITION;

        v_contract_key_list               t_contract_key_list;
        v_index                           BINARY_INTEGER;

        v_qty_long                        INTEGER;
        v_qty_short                       INTEGER;

        v_option_type                     VARCHAR2(1);
        v_invalid_order                   BOOLEAN :=FALSE;
    BEGIN
        p_check_cond_met := 'N';


        IF     order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'C'
           AND NVL(RTRIM(order_val_check_functions.v_validation_data.WORKING_ORDER_REC.COLLECTIVE_ORDER_TYPE), ' ') <> 'OAO'
        THEN
            v_qty_short      := 0;
            v_qty_long       := 0;

            v_option_type := order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE;

            -- for futures all positions have to be summed up to receive accurate quantities
            IF (v_option_type = 'F')
            THEN
                WITH positions
                AS (
                    SELECT TREAT(VALUE(p) AS T_CFT_POSITION).getQuantity(TREAT(VALUE(p) AS T_CFT_POSITION).qty_short) AS qty_short,
                           TREAT(VALUE(p) AS T_CFT_POSITION).getQuantity(TREAT(VALUE(p) AS T_CFT_POSITION).qty_long) AS qty_long,
                           TREAT(p.pk AS T_CFT_POSITION_KEY).getInstrumentId() AS contract_key
                    FROM   POSITION p
                    WHERE  p.pk.aggregation_level                             = 2
                       AND TREAT(p.pk AS T_CFT_POSITION_KEY).getAccountNo()   = RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO)
                       AND TREAT(p.pk AS T_CFT_POSITION_KEY).getAccountType() = order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE
                       AND TREAT(p.pk AS T_CFT_POSITION_KEY).getTeam()        = order_val_check_functions.v_validation_data.TEAM_NAME
                       AND TREAT(p.pk AS T_CFT_POSITION_KEY).getExchangeId()  = order_val_check_functions.v_validation_data.EXCH_KEY
                ),
                contracts
                AS (
                    SELECT CONTRACT_KEY
                    FROM   FO_CONTRACT foc
                    WHERE  foc.WKN = order_val_check_functions.v_validation_data.WKN
                     AND   foc.CNTR_STATUS_CODE = 'A'
                )
                SELECT SUM(qty_short), SUM(qty_long)
                INTO   v_qty_short, v_qty_long
                FROM   positions p JOIN contracts c ON (p.contract_key = c.CONTRACT_KEY);

                IF ((v_qty_long > 0) AND (v_qty_short > 0))
                THEN
                    v_invalid_order := TRUE;
                END IF;
            ELSIF v_option_type IN ('C', 'P') -- for options all positions on contract level are summed up
            THEN
                v_position := T_CFT_POSITION(
                    level           => 2,
                    p_team          => order_val_check_functions.v_validation_data.TEAM_NAME,
                    p_instrument_id => order_val_check_functions.v_validation_data.CONTRACT_KEY,
                    p_exchange_id   => order_val_check_functions.v_validation_data.EXCH_KEY,
                    p_account_no    => RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO),
                    p_account_type  => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
                    p_order_no      => NULL,
                    p_trade_id      => NULL,
                    p_attributes    => NULL);

                v_current_position := TREAT(session_store.object_store.get(v_position) AS T_CFT_POSITION);

                IF    v_current_position.qty_long IS NULL
                   OR v_current_position.qty_short IS NULL
                THEN
                    v_invalid_order := TRUE;
                ELSIF     v_current_position.getQuantity(v_current_position.qty_long) > 0
                      AND v_current_position.getQuantity(v_current_position.qty_short) > 0
                THEN
                    v_invalid_order := TRUE;
                END IF;
            END IF; -- OPTION_TYPE
        END IF; -- CLOSING ORDER

        IF v_invalid_order
        THEN
            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40050),
                    p_check_cond_met => p_check_cond_met);
        END IF;

        EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0050',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; customer_depot_type = ' ||
                    order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE ||
                    '; team_name = ' ||
                    order_val_check_functions.v_validation_data.TEAM_NAME ||
                    '; contract_key = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_KEY ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0050',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; customer_depot_type = ' ||
                    order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE ||
                    '; team_name = ' ||
                    order_val_check_functions.v_validation_data.TEAM_NAME ||
                    '; contract_key = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_KEY ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0050;


    /*
    ** Checks, if stock is greater than zero for closing order
    ** sp_fo_position_closable_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0060(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_current_position      T_CFT_POSITION;
        v_position              T_CFT_POSITION;

        v_deal_type         VARCHAR2(10);

    BEGIN
        p_check_cond_met := 'N';

        -- Closing on simple contracts only, do not evaluate for complex instruments.
        -- [#54062]
        IF     order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'C'
           AND order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE <> 'M'
        THEN
            v_deal_type := order_val_check_functions.v_validation_data.DEAL_TYPE;

            -- validates only orders that are buy, sell, or exercise orders
            IF (v_deal_type = 'B' OR v_deal_type = 'S' OR v_deal_type = 'X')
            THEN
                v_position := T_CFT_POSITION(
                    level           => 2,
                    p_team          => order_val_check_functions.v_validation_data.TEAM_NAME,
                    p_instrument_id => order_val_check_functions.v_validation_data.CONTRACT_KEY,
                    p_exchange_id   => order_val_check_functions.v_validation_data.EXCH_KEY,
                    p_account_no    => RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO),
                    p_account_type  => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
                    p_order_no      => NULL,
                    p_trade_id      => NULL,
                    p_attributes    => NULL);

                v_current_position := TREAT(session_store.object_store.get(v_position) AS T_CFT_POSITION);

                IF          v_current_position.qty_short IS NULL
                   OR       v_current_position.qty_long IS NULL
                   OR (     v_deal_type = 'B'
                       AND (v_current_position.getQuantity(v_current_position.qty_short)
                          - v_current_position.getQuantity(v_current_position.qty_short_dispo_close)) < 0
                      )
                   OR (     v_deal_type <> 'B'
                       AND (v_current_position.getQuantity(v_current_position.qty_long)
                          - v_current_position.getQuantity(v_current_position.qty_long_dispo_close)) < 0
                      )
                THEN
                    order_val_check_functions.sp_handle_message(
                        p_validation     => p_validation,
                        p_message        => error.format(40060),
                        p_check_cond_met => p_check_cond_met);
                END IF;
            END IF; -- DEAL_TYPE
        END IF; -- CLOSING ORDER
    END sp_order_val_check_0060;

    /*
    ** Checks, if the order's validity is within the customer's futures trading ability
    ** sp_bt_exp_date_fdc_exp_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0070(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_end_date_char     VARCHAR2(64);
        v_end_date          DATE;
        v_foc_expiry_date   FO_CONTRACT.CNTR_EXPIRATION_DATE%TYPE;

        v_length            NUMBER;
        v_invalid_order     BOOLEAN := FALSE;
    BEGIN
        p_check_cond_met := 'N';

        -- only for opening orders
        IF ( order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'O')
        THEN
            SELECT c.VALUE
            INTO v_end_date_char
            FROM EXT_CUSTOMER_ATTRIBUTES c
            WHERE c.CUSTOMER_NO    =
                     order_val_check_functions.v_validation_data.CUSTOMER_NO
            AND   c.ATTRIBUTE_TYPE = 'CUST_KIM'
            AND   c.KEY            = 'FwdEndDate';

            -- it is possible that there are other values than a date
            SELECT LENGTH(v_end_date_char) INTO v_length FROM SYS.DUAL;
            IF (v_length <> 8)
            THEN
                v_invalid_order := TRUE;
            ELSE
                -- it is a date value
                SELECT TO_DATE(v_end_date_char, 'YYYYMMDD') INTO v_end_date FROM SYS.DUAL;

                -- if it is 'Good Till Cancel', test the contract's expiry date
                IF ( order_val_check_functions.v_validation_data.TRADING_RESTR_CODE = 'GTC')
                THEN

                    v_foc_expiry_date := order_val_check_functions.v_validation_data.CONTRACT_REC.EXPIRATION_DATE;

                    v_invalid_order := v_foc_expiry_date IS NULL OR (TRUNC(v_foc_expiry_date) > TRUNC(v_end_date));

                    -- else test the order's expiry date
                ELSE
                    v_invalid_order := v_end_date IS NULL OR
                       (TRUNC(order_val_check_functions.v_validation_data.EXPIRY) > TRUNC(v_end_date));
                END IF; -- TRADING_RESTR_CODE
            END IF; -- END DATE IS A VALID DATE
        END IF; -- OPENING ORDER

        IF v_invalid_order
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40070),
                p_check_cond_met => p_check_cond_met);
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0070',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; EXT_CUSTOMER_ATTRIBUTES CUST_KIM FwdEndDate = ' || v_end_date_char ||
                    '; trading_restr_code = ' ||
                    order_val_check_functions.v_validation_data.TRADING_RESTR_CODE ||
                    '; contract''s restriction date = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_REC.EXPIRATION_DATE ||
                    '; expiry = ' ||
                    order_val_check_functions.v_validation_data.EXPIRY,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0070',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; EXT_CUSTOMER_ATTRIBUTES CUST_KIM FwdEndDate = ' || v_end_date_char ||
                    '; trading_restr_code = ' ||
                    order_val_check_functions.v_validation_data.TRADING_RESTR_CODE ||
                    '; contract''s restriction date = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_REC.EXPIRATION_DATE ||
                    '; expiry = ' ||
                    order_val_check_functions.v_validation_data.EXPIRY,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0070;


    /*
    ** Checks, if the order's expiry date is within a year starting today
    ** sp_fo_exp_date_valid_date_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0080(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_today_plus_a_year               DATE;
    BEGIN
        p_check_cond_met := 'N';

        -- if it is 'Good Till Cancel', no check required
        IF NOT( order_val_check_functions.v_validation_data.TRADING_RESTR_CODE = 'GTC')
        THEN
            SELECT add_months(TRUNC(SYSDATE),12) INTO v_today_plus_a_year FROM SYS.DUAL;

            IF   v_today_plus_a_year IS NULL
              OR (order_val_check_functions.v_validation_data.EXPIRY > v_today_plus_a_year)
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40080),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        -- NO BUSINESS DAY CHECK BECAUSE OF SP_ORDER_VAL_CHECK_0020
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0080',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; trading_restr_code = ' ||
                    order_val_check_functions.v_validation_data.TRADING_RESTR_CODE ||
                    '; expiry = ' ||
                    order_val_check_functions.v_validation_data.EXPIRY,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0080',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; trading_restr_code = ' ||
                    order_val_check_functions.v_validation_data.TRADING_RESTR_CODE ||
                    '; expiry = ' ||
                    order_val_check_functions.v_validation_data.EXPIRY,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0080;


    /*
    ** Checks, if the order is coverable
    ** sp_fo_order_covered_test
    ** hard check
    */
    PROCEDURE sp_order_val_check_0090(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
        p_check_cond_met := 'N';

        IF (    order_val_check_functions.v_validation_data.COVERED_INDICATOR = 'C')
        THEN
          IF (   order_val_check_functions.v_validation_data.BUY_SELL <> 'S'
                OR order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR <> 'O'
                OR contract_tool.is_contract_coverable(order_val_check_functions.v_validation_data.CONTRACT_REC) <> 'Y')
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40090),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0090',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; buy_sell = ' ||
                    order_val_check_functions.v_validation_data.BUY_SELL ||
                    '; covered_indicator = ' ||
                    order_val_check_functions.v_validation_data.COVERED_INDICATOR,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0090',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; buy_sell = ' ||
                    order_val_check_functions.v_validation_data.BUY_SELL ||
                    '; covered_indicator = ' ||
                    order_val_check_functions.v_validation_data.COVERED_INDICATOR,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0090;

    -- validation #100 already reserved by ORDER_VAL_CHECK_FUNCTIONS

    /*
    ** Checks, if stop limit and limit are set correctly
    ** hard check
    */
    PROCEDURE sp_order_val_check_0110(
        p_validation              IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met             OUT NOCOPY usertype.YESNO)
    IS
        v_limit                NUMBER;
        v_stop_limit           NUMBER;
        v_buy_sell             CHAR(1);
        v_limit_type           CHAR(1);
    BEGIN
        p_check_cond_met := 'N';

        v_limit_type := NVL(order_val_check_functions.v_validation_data.LIMIT_TYPE,
                            order_tool.limit_type_bestens);
        v_limit            := NVL(TO_NUMBER(order_val_check_functions.v_validation_data.LIMIT1), 0);
        v_stop_limit := NVL(TO_NUMBER(order_val_check_functions.v_validation_data.LIMIT2), 0);

        v_buy_sell   := order_val_check_functions.v_validation_data.BUY_SELL;

        IF (     v_limit_type = order_tool.limit_type_oco
            AND (   (v_buy_sell = order_tool.BUY  AND (v_stop_limit <= v_limit))
                 OR (v_buy_sell = order_tool.SELL AND (v_stop_limit >= v_limit))
                )
           )
           OR
           (     v_limit_type = order_tool.limit_type_stop_limit
            AND (   (v_buy_sell = order_tool.SELL  AND (v_stop_limit <= v_limit))
                 OR (v_buy_sell = order_tool.BUY AND (v_stop_limit >= v_limit))
                )
           )
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40110),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END sp_order_val_check_0110;

    /*
    ** Checks, if operation on order happens beyond trading time
    ** hard check
    */
    PROCEDURE sp_order_val_check_0120(
        p_validation            IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met           OUT NOCOPY usertype.YESNO)
    IS
        v_beyond_trading    BOOLEAN;
    BEGIN

        IF order_val_check_functions.v_validation_data.ALREADY_DEALT <> 'Y'
        THEN
            v_beyond_trading := exchange_tool.no_trading(
                p_exch_key => order_val_check_functions.v_validation_data.EXCH_KEY,
                p_wkn      => order_val_check_functions.v_validation_data.WKN);

            IF v_beyond_trading
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40120),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0120',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; already_dealt = ' ||
                    order_val_check_functions.v_validation_data.ALREADY_DEALT ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY ||
                    '; wkn = ' ||
                    order_val_check_functions.v_validation_data.WKN,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0120',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; already_dealt = ' ||
                    order_val_check_functions.v_validation_data.ALREADY_DEALT ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY ||
                    '; wkn = ' ||
                    order_val_check_functions.v_validation_data.WKN,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0120;

    /*
    ** Checks, if spanish account has a closing or an option
    ** hard check
    */
    PROCEDURE sp_order_val_check_0130(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_account_country                 VARCHAR2(2);

    BEGIN
        p_check_cond_met := 'N';

        v_account_country := customer_tool.split_account_no(
                                 p_account_no => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO,
                                 p_part       => customer_tool.account_branch);
        IF v_account_country = 'ES'
        THEN
            IF    order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE = 'O'
               OR order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'C'
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40130),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0130',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; option_type = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE ||
                    '; account_country = ' || v_account_country,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0130',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; option_type = ' ||
                    order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE ||
                    '; account_country = ' || v_account_country,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0130;


    /*
    ** Checks the risk profile of the current user
    ** hard check
    */
    PROCEDURE sp_order_val_check_0140(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_user_id              usertype.USER_ID;
        v_user_risk            VARCHAR2(20);

    BEGIN
        p_check_cond_met := 'N';

        IF ( order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'O')
        THEN

            v_user_id := usersession.get_user;

            SELECT TRIM(RISK_PROFILE)
            INTO v_user_risk
            FROM OROM_USER
            WHERE USER_INITIAL = v_user_id;

            /*
            ** if no risk profil is set for current user,
            ** there is no restriction on the products the
            ** user is allowed to trade
            ** so no validation is required
            */
            IF v_user_risk IS NULL
            THEN
                RETURN;
            END IF;

            IF NVL(check_risk_profile(p_validation, p_check_cond_met, v_user_risk), FALSE)
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40140),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0140',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || v_user_id ||
                    '; user_risk = ' || v_user_risk,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.sp_order_val_check_0140',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || v_user_id ||
                    '; user_risk = ' || v_user_risk,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END sp_order_val_check_0140;


    /*
    ** Margin checks on an account.
    ** Validation messages: 40150-40153
    */
    PROCEDURE sp_order_val_check_0150(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        a                                 T_GM_VARRAY_VARCHAR2 := T_GM_VARRAY_VARCHAR2();
        v_amounts                         T_NUMBER_ARRAY       := T_NUMBER_ARRAY(0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        v_team                            TEAM%ROWTYPE;

        v_total_obligation                NUMBER               := 0;

        -- Extended attributes of account and margin account.
        v_account_attributes              ext_attributes.t_ext_attribute_list;
        v_margin_account_attributes       ext_attributes.t_ext_attribute_list;
        v_margin_account_no               usertype.ACCOUNT_NO;
        v_margin_account_curr             usertype.CURRENCY;

        v_amount_1                        NUMBER;
        v_amount_2                        NUMBER;
        v_amount_3                        NUMBER;
        v_amount_4                        NUMBER;
        v_margin_factor                   NUMBER;
        v_asset_margin                    NUMBER;
        v_cover_ratio                     NUMBER;

        v_fo_contract_data                T_CONTRACT;
        v_message_severity                INTEGER;

    BEGIN
        p_check_cond_met := 'N';

        sp_team_select (
            p_team_name => order_val_check_functions.v_validation_data.TEAM_NAME,
            p_team      => v_team);

        -- only check if opening order
        IF order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'C'
        THEN
            RETURN;
        END IF;

        -- only check if uncovered order
        IF order_val_check_functions.v_validation_data.COVERED_INDICATOR = 'C'
        THEN
            RETURN;
        END IF;

        -- only check if account margin check of team is selected
        IF v_team.ACCT_MARGIN_CHECK = 'N'
        THEN
            RETURN;
        END IF;

        IF session_store.get_value('cft_order_val_check_functions.0150.theo_price_not_found') IS NOT NULL
        THEN
            v_message_severity := p_validation.MESSAGE_SEVERITY;

            SELECT VALUE(fcd)
            INTO   v_fo_contract_data
            FROM   FO_CONTRACT_DATA fcd
            WHERE  CONTRACT_KEY = TO_NUMBER(session_store.get_value('cft_order_val_check_functions.0150.theo_price_not_found'));

            -- Validation Id 150
            -- Raise severity for sells or futures or complex instruments.
            IF    order_val_check_functions.v_validation_data.BUY_SELL = order_tool.sell
               OR order_val_check_functions.v_validation_data.CONTRACT_REC.MGN_STYL_TYP = 'F'
            THEN p_validation.MESSAGE_SEVERITY := error.severity_error;
            END IF;

            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(13700, contract_tool.format_contract_id(v_fo_contract_data)),
                p_check_cond_met => p_check_cond_met);

            p_validation.MESSAGE_SEVERITY := v_message_severity;
        END IF;

        sp_margin_obligo_calc(
            p_account_no     => RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO),
            p_account_type   => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
            p_object_store   => session_store.object_store,
            p_mo_amount      => v_amounts,
            p_mo_info        => a);

        v_total_obligation := a(T_DISPO_MGMT_EVENT.overall_debit);

        -- Extended attributes of account and margin account are needed. Therefore we need
        -- the margin account no. first.
        ext_attributes.get(
            p_collection     => 'EXT_ACCOUNT_ATTRIBUTES',
            p_key1           => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO,
            p_key2           => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
            p_attribute_list => v_account_attributes);

        v_margin_account_no   := ext_attributes.read(v_account_attributes, 'ACCT_KIM', 'MargAccNo');
        v_margin_account_curr := ext_attributes.read(v_account_attributes, 'ACCT_KIM', 'MargAccCurr');

        ext_attributes.get(
            p_collection     => 'EXT_CASH_ACCOUNT_ATTRIBUTES',
            p_key1           => v_margin_account_no,
            p_key2           => v_margin_account_curr,
            p_attribute_list => v_margin_account_attributes);

        v_asset_margin := NVL(TO_NUMBER(ext_attributes.read(v_account_attributes,        'ACCT_KRDB', 'OverallBal')),    0)
                        + NVL(TO_NUMBER(ext_attributes.read(v_account_attributes,        'ACCT_KRDB', 'StckValRated')),  0)
                        - NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KRDB', 'Credit')),        0)
                        - NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KRDB', 'IntCredit')),     0);

        -- assets check 1
        IF ext_attributes.read(v_margin_account_attributes, 'CACC_KIM', 'CapMargCheck') = 'Y'
        THEN
            -- Respect margin factor in v_amounts(5).
            v_margin_factor := NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KIM', 'MargFactor')), 100) / 100;

            v_amount_2 :=   v_asset_margin
                          - (                                                                                                 -- Aggregated margin
                                v_amounts(5)
                              + NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'MargCorr')),  0)
                            )
                          * (v_margin_factor - 1);                                                                            -- Margin factor

            IF v_amount_2 < 0
            THEN
                -- Validation Id 152
                p_validation.VALIDATION_ID := 152;
                    order_val_check_functions.sp_handle_message(
                        p_validation     => p_validation,
                        p_message        => error.format(40151, format.fmt_number (- v_amount_2, 2)),
                        p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;

        v_amount_4 := NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KRDB', 'Credit')), 0)
                    + NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KRDB', 'IntCredit')),0)
                    + NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'CashCorr')), 0)
                    - v_total_obligation
                    - NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'MargCorr')), 0);

        -- EUREX limits check
        IF v_amount_4 < 0
        THEN
            -- Validation Id 154
            v_cover_ratio := sp_compute_cover_ratio(
                                 p_amounts                => v_amounts,
                                 p_margin_factor          => cft_margin_tool.get_eff_margin_factor(
                                                                 ext_attributes.read(v_margin_account_attributes, 'CACC_KIM', 'CapMargCheck'),
                                                                 ext_attributes.read(v_margin_account_attributes, 'CACC_KIM', 'MargFactor')
                                                             ),
                                 p_overall_balance        => NVL(TO_NUMBER(ext_attributes.read(v_account_attributes,        'ACCT_KRDB', 'OverallBal')),    0),
                                 p_stock_value_rated      => NVL(TO_NUMBER(ext_attributes.read(v_account_attributes,        'ACCT_KRDB', 'StckValRated')),  0),
                                 p_cash_correction        => NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'CashCorr')),      0),
                                 p_margin_correction      => NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'MargCorr')),      0)
                             );

            p_validation.VALIDATION_ID := 154;
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40153, format.fmt_number (- v_amount_4, 2)),
                p_check_cond_met => p_check_cond_met
            );

            sp_order_val_msg_details_ins(
                p_validation_id => p_validation.VALIDATION_ID,
                p_message_type  => resultset_format.resultset_format_record,
                p_col_01        => resultset_format.get_lchar_format()
            );

            sp_order_val_msg_details_ins(
                p_validation_id => p_validation.VALIDATION_ID,
                p_message_type  => resultset_format.resultset_header_record,
                p_col_01        => userobject.get_description(userobject.column_code, 'DESCRIPTION')
            );

            sp_order_val_msg_details_ins(
                p_validation_id => p_validation.VALIDATION_ID,
                p_message_type  => resultset_format.resultset_data_record,
                p_col_01        => error.format(40154, format.fmt_number(NVL(v_cover_ratio, 0), 2, usersession.get_language))
            );
        END IF;

        -- check margin limit overdraft
        v_amount_1 := a(T_DISPO_MGMT_EVENT.margin)
            + NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_TRAD', 'MargCorr')), 0)   -- Margin correction
            - NVL(TO_NUMBER(ext_attributes.read(v_margin_account_attributes, 'CACC_KIM',  'MargLimit')), 0); -- Margin limit

        IF v_amount_1 > 0
        THEN
            -- Validation Id 151
            p_validation.VALIDATION_ID := 151;
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40150, format.fmt_number (v_amount_1, 2)),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END sp_order_val_check_0150;


    /*
    ** Margin limit checks on business area level.
    ** Validation messages: 40160
    */
    PROCEDURE sp_order_val_check_0160(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_team                            TEAM%ROWTYPE;
        v_total_margin_obligation         NUMBER;
        v_diff                            NUMBER;
        v_amounts                         T_NUMBER_ARRAY := T_NUMBER_ARRAY (0, 0, 0, 0, 0, 0, 0, 0, 0, 0);
        a                                 T_GM_VARRAY_VARCHAR2 := T_GM_VARRAY_VARCHAR2();

    BEGIN
        p_check_cond_met := 'N';

        sp_team_select (
            p_team_name => order_val_check_functions.v_validation_data.TEAM_NAME,
            p_team      => v_team);

        -- only check if margin check of team is selected
        IF v_team.MARGIN_CHECK = 'N'
        THEN
            RETURN;
        END IF;

        sp_margin_obligo_calc (
            p_account_no    => v_team.TEAM_NAME,
            p_account_type  => 'A',
            p_object_store  => session_store.object_store,
            p_mo_amount     => v_amounts,
            p_mo_info       => a);

        v_diff := a(T_DISPO_MGMT_EVENT.margin) - v_team.MARGIN_LIMIT;

        IF v_diff > 0
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40160, format.fmt_number (v_diff, 2)),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END sp_order_val_check_0160;


    /*
    ** Checks, if underlying stock is sufficient for covered order.
    ** Validation messages: 2450
    */
    PROCEDURE sp_order_val_check_0170(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_cft_underlying_position         T_CFT_UNDERLYING_POSITION;
        v_lock_quantity                   NUMBER;
    BEGIN
        p_check_cond_met := 'N';

        IF order_val_check_functions.v_validation_data.COVERED_INDICATOR = 'C'
        THEN
            -- only an integer number of shares can be locked
            v_lock_quantity := FLOOR(  (  order_val_check_functions.v_validation_data.QUANTITY
                                        - NVL(order_val_check_functions.v_validation_data.OLD_ORDER_REC.QUANTITY, 0))
                                     * order_val_check_functions.v_validation_data.CONTRACT_REC.TRD_UNIT_NO);

            v_cft_underlying_position := T_CFT_UNDERLYING_POSITION(
                                             RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO),
                                             order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
                                             order_val_check_functions.v_validation_data.CONTRACT_REC.UNDERLYING_WKN);

            IF v_cft_underlying_position.getQuantity() < v_lock_quantity
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(
                                            error.local_uly_lock_exceed_fail,
                                            order_val_check_functions.v_validation_data.ORDER_NO,
                                            v_lock_quantity,
                                            v_cft_underlying_position.getQuantity()),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;
    END sp_order_val_check_0170;


    /*
    ** Checks, if account is eligible for US-trading.
    */
    PROCEDURE sp_order_val_check_0200(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
            -- Exchange is in domain 'US'...
        IF     sp_exchange_is_in_domain(
                   p_domain   => 'US',
                   p_exch_key => order_val_check_functions.v_validation_data.EXCH_KEY)               = 'Y'

           -- ... and account is not enabled for US-trading.
           AND sp_acct_is_enabled_for_domain(
                   p_domain       => 'US',
                   p_account_no   => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO,
                   p_account_type => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE) = 'N'
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(
                                        40300,
                                        RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO)
                                    ),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END sp_order_val_check_0200;


    /*
     * 210/211
     * US Exchanges
     * Check if resultant position is long and short.
     */
    PROCEDURE perform_val_210_211(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_position         T_CFT_POSITION;
        v_current_position T_CFT_POSITION;
    BEGIN
        v_position := T_CFT_POSITION(
            level           => 2,
            p_team          => order_val_check_functions.v_validation_data.TEAM_NAME,
            p_instrument_id => order_val_check_functions.v_validation_data.CONTRACT_KEY,
            p_exchange_id   => order_val_check_functions.v_validation_data.EXCH_KEY,
            p_account_no    => RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO),
            p_account_type  => order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_TYPE,
            p_order_no      => NULL,
            p_trade_id      => NULL,
            p_attributes    => NULL);

        v_current_position := TREAT(session_store.object_store.get(v_position) AS T_CFT_POSITION);

        IF    (  v_current_position.getQuantity(v_current_position.qty_long)
               + v_current_position.getQuantity(v_current_position.qty_long_dispo_open)
               + v_current_position.getQuantity(v_current_position.qty_long_dispo_close))  <> 0
          AND (  v_current_position.getQuantity(v_current_position.qty_short)
               + v_current_position.getQuantity(v_current_position.qty_short_dispo_open)
               + v_current_position.getQuantity(v_current_position.qty_short_dispo_close)) <> 0
        THEN
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => error.format(40210),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END;

    /*
     * Future Trader:
     * Check does not dependent on open/close type of order.
     */
    PROCEDURE sp_order_val_check_0210(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
        p_check_cond_met := 'N';
        perform_val_210_211(p_validation, p_check_cond_met);
    END sp_order_val_check_0210;

    /*
     * Power.Trader:
     * Perform check for opening orders only.
     */
    PROCEDURE sp_order_val_check_0211(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
    BEGIN
        p_check_cond_met := 'N';

        IF order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR = 'O'
        THEN
            perform_val_210_211(p_validation, p_check_cond_met);
        END IF;
    END sp_order_val_check_0211;

    /*
    ** US options Delta check
    */
    PROCEDURE sp_order_val_check_0220(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_fo_contract_ext_attr  FO_CONTRACT_EXTENDED_ATTR%ROWTYPE;
        v_delta                 NUMBER;
        v_us_delta_chk          NUMBER;
        v_min_delta             NUMBER;
        v_max_delta             NUMBER;
    BEGIN
        p_check_cond_met := 'N';

        IF     order_val_check_functions.v_validation_data.EXCHANGE_REC.COUNTRY    = 'US'
           AND rtrim(order_val_check_functions.v_validation_data.CONTRACT_REC.PROD_TYPE) <> 'FUTURE'
           AND order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR    = 'O'
        THEN
            contract_tool.fo_contract_ext_attr_select(
                p_contract_key         => order_val_check_functions.v_validation_data.CONTRACT_KEY,
                p_attribute_type       => 'Greeks',
                p_key                  => 'Delta',
                p_strict               => FALSE,
                p_fo_contract_ext_attr => v_fo_contract_ext_attr);

            v_delta := TO_NUMBER(v_fo_contract_ext_attr.VALUE);

            IF order_val_check_functions.v_validation_data.CONTRACT_REC.CNTR_EXPIRATION_DATE <= TO_DATE('20171231', 'YYYYMMDD')
            THEN v_us_delta_chk := 0.95;
            ELSE v_us_delta_chk := TO_NUMBER(parameter_tool.get_parameter_value('US_DELTA_CHK'));
            END IF;

            v_min_delta := -1 * v_us_delta_chk;
            v_max_delta :=      v_us_delta_chk;

            IF v_min_delta < v_delta AND v_delta < v_max_delta
            THEN
                NULL;  -- Opening allowed
            ELSE
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(
                                            40220,
                                            format.fmt_number(v_delta,     2, common_tool.lang_code_english),
                                            format.fmt_number(v_min_delta, 2, common_tool.lang_code_english),
                                            format.fmt_number(v_max_delta, 2, common_tool.lang_code_english)),
                    p_check_cond_met => p_check_cond_met);
            END IF;
        END IF;
    END sp_order_val_check_0220;


    /*
    ** only day orders for instruments traded during eurex extended trading times
    */
    PROCEDURE sp_order_val_check_0230(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_day_orders_only       CHAR(1);
        v_validate_params       strat_tool.t_validate_params;
        v_closing_leg_expiry    DATE;
    BEGIN
        p_check_cond_met := 'N';

        SELECT DECODE (COUNT(*),1,'Y','N')
        INTO   v_day_orders_only
        FROM   FO_PRODUCT_DAY_ORDERS_ONLY
        WHERE  WKN = order_val_check_functions.v_validation_data.WKN;

        IF v_day_orders_only = 'Y'
        THEN
            -- For an OAO order get expi of closing leg. If not an OAO order
            -- assume 'today' as expi which will dispable check.
            IF order_val_check_functions.v_validation_data.STRATEGY_NAME = 'OAO'
            THEN
                SELECT PARAM_NAME, VALUE
                BULK COLLECT INTO v_validate_params.pred_params
                FROM   ORDER_STRATEGY_PARAMS_TMP;

                v_closing_leg_expiry := TO_DATE(strat_tool.get_strat_param('EXPIRYDATE', v_validate_params.pred_params),'YYYYMMDD');

                IF v_closing_leg_expiry IS NULL
                THEN
                    v_closing_leg_expiry := oao.get_expiry_date(
                        p_wkn                 => order_val_check_functions.v_validation_data.WKN,
                        p_exch_key            => order_val_check_functions.v_validation_data.EXCH_KEY,
                        p_strategy_parameters => v_validate_params.pred_params);
                END IF;
            ELSE
                v_closing_leg_expiry := SYSDATE;
            END IF;

            -- All legs, if more than one at all, must be  day orders.
            IF    TRUNC(NVL(order_val_check_functions.v_validation_data.expiry, SYSDATE+1)) <> TRUNC(SYSDATE)
               OR TRUNC(NVL(v_closing_leg_expiry, SYSDATE+1)) <> TRUNC(SYSDATE)
            THEN
                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40230),
                    p_check_cond_met => p_check_cond_met);
            ELSE
                NULL; -- order allowed
            END IF;
        ELSE
            NULL;  -- order allowed
        END IF;
    END sp_order_val_check_0230;

    /*
    ** "SOA" set in customer info text
    */
    PROCEDURE sp_order_val_check_0240(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO)
    IS
        v_customer_attributes ext_attributes.t_ext_attribute_list;
    BEGIN
        p_check_cond_met := 'N';

        ext_attributes.get(
            p_collection     => 'EXT_CUSTOMER_ATTRIBUTES',
            p_key1           => order_val_check_functions.v_validation_data.CUSTOMER_NO,
            p_attribute_list => v_customer_attributes);

        -- Check condition is met when info text contains SOA.
        IF INSTR(UPPER(ext_attributes.read(v_customer_attributes, 'CUST_TRAD', 'InfoText')), 'SOA') > 0
        THEN
            p_validation.VALIDATION_ID := 240;
            order_val_check_functions.sp_handle_message(
                p_validation     => p_validation,
                p_message        => ext_attributes.read(v_customer_attributes, 'CUST_TRAD', 'InfoText'),
                p_check_cond_met => p_check_cond_met);
        END IF;
    END;

    /*
    ** Contains the common part of risk profile check
    */
    FUNCTION check_risk_profile(
        p_validation        IN OUT NOCOPY T_VALIDATION_OBJECT,
        p_check_cond_met       OUT NOCOPY usertype.YESNO,
        p_risk_profile      IN            VARCHAR2)
    RETURN BOOLEAN
    AS
        v_option_type          VARCHAR2(1);
        v_result               VARCHAR2(4000);
        v_prod_type            CHAR(12);
        v_exch_no              CHAR(5);
        v_buy_sell             CHAR(1);
        v_covered_ind          CHAR(1);
        v_max_qty              NUMBER(18, 4);
        v_tmp                  NUMBER;

    BEGIN
        -- testing if order is a future or an option
        v_option_type := order_val_check_functions.v_validation_data.CONTRACT_REC.OPTION_TYPE;


        -- defining product category
        SELECT p.PROD_TYPE
        INTO v_prod_type
        FROM FO_PRODUCT p
        WHERE p.WKN = order_val_check_functions.v_validation_data.WKN;

        -- defining trading place
        SELECT e.EXCH_NO
        INTO v_exch_no
        FROM EXCH e
        WHERE e.EXCH_KEY = order_val_check_functions.v_validation_data.EXCH_KEY;

        -- setting robs attributes to compute a result set
        robs_attributes.init_attributes;
        robs_attributes.set_attribute(RTRIM(p_risk_profile), 'RISK_PROFILE');
        robs_attributes.set_attribute(RTRIM(v_exch_no),      'EXCH.EXCH_NO');
        robs_attributes.set_attribute(RTRIM(v_prod_type),    'FO_PRODUCT.PROD_TYPE');
        -- computation of result set for given risk profile
        robs_attributes.match(
            p_rule_set_space_type    => robs_attributes.SPACE_TYPE_RISK_PROFILE,
            p_outcome_attrib         => v_result);

        v_max_qty :=  NVL (robs_attributes.get_value(
            p_value_name => 'MAX_QTY',
            p_string     => v_result), '0');

        -- validation begins here

        -- for futures just check the quantity

        -- number of contracts must be smaller or equal
        -- than the maximum of allowed contracts
        IF (order_val_check_functions.v_validation_data.QUANTITY > v_max_qty )
        THEN
            RETURN TRUE;
        ELSIF (v_option_type <> 'F')  -- for options additional checks are required
        THEN
            v_buy_sell := order_val_check_functions.v_validation_data.BUY_SELL;
            v_covered_ind := order_val_check_functions.v_validation_data.COVERED_INDICATOR;


            IF ( v_option_type = 'C' AND  v_buy_sell = 'B'
                -- long call must be allowed
                AND  NVL (RTRIM ( robs_attributes.get_value(
                         p_value_name => '->LONG_CALL',
                         p_string     => v_result)), 'N')    <> 'Y'
               )
            OR ( v_option_type = 'C' AND v_buy_sell = 'S' AND v_covered_ind = 'C'
                -- short call covered must be allowed
                AND NVL (RTRIM ( robs_attributes.get_value(
                        p_value_name => '->SHORT_CALL_COVERED',
                        p_string     => v_result)), 'N')    <> 'Y'
               )
            OR ( v_option_type = 'C' AND v_buy_sell = 'S' AND v_covered_ind = 'U'
                -- short call uncovered must be allowed
                AND NVL (RTRIM ( robs_attributes.get_value(
                        p_value_name => '->SHORT_CALL_UNCOVERED',
                        p_string     => v_result)), 'N')    <> 'Y'
               )
            OR ( v_option_type = 'P' AND v_buy_sell = 'B'
                -- long put must be allowed
                AND NVL (RTRIM ( robs_attributes.get_value(
                        p_value_name => '->LONG_PUT',
                        p_string     => v_result)), 'N')    <> 'Y'

               )
            OR ( v_option_type = 'P' AND v_buy_sell = 'S'
                -- long put must be allowed
                AND NVL (RTRIM ( robs_attributes.get_value(
                        p_value_name => '->SHORT_PUT',
                        p_string     => v_result)), 'N')    <> 'Y'
               )
            THEN
                RETURN TRUE;
            END IF;
        END IF;

        RETURN FALSE;

    EXCEPTION
        WHEN NO_DATA_FOUND
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.check_risk_profile',
                p_message  => 'NO_DATA_FOUND ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; wkn = ' ||
                    order_val_check_functions.v_validation_data.WKN ||
                    '; FO_PRODUCT type = ' || v_prod_type ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY ||
                    '; exch_no = ' || v_exch_no ||
                    '; option_type = ' || v_option_type ||
                    '; risk_profile = ' || p_risk_profile ||
                    '; buy_sell = ' || v_buy_sell ||
                    '; covered_indicator = ' || v_covered_ind,
                p_severity => error.severity_info);

                order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'cft_order_val_check_functions.check_risk_profile',
                p_message  => 'OTHERS ERROR: open_close = ' ||
                    order_val_check_functions.v_validation_data.OPEN_CLOSE_INDICATOR ||
                    '; customer_depot_no = ' ||
                    RTRIM(order_val_check_functions.v_validation_data.CUSTOMER_DEPOT_NO) ||
                    '; user_id = ' || usersession.get_user ||
                    '; wkn = ' ||
                    order_val_check_functions.v_validation_data.WKN ||
                    '; FO_PRODUCT type = ' || v_prod_type ||
                    '; exch_key = ' ||
                    order_val_check_functions.v_validation_data.EXCH_KEY ||
                    '; exch_no = ' || v_exch_no ||
                    '; option_type = ' || v_option_type ||
                    '; risk_profile = ' || p_risk_profile ||
                    '; buy_sell = ' || v_buy_sell ||
                    '; covered_indicator = ' || v_covered_ind,
                p_severity => error.severity_info);

            order_val_check_functions.sp_handle_message(
                    p_validation     => p_validation,
                    p_message        => error.format(40000),
                    p_check_cond_met => p_check_cond_met);

    END check_risk_profile;

END cft_order_val_check_functions;
/

SHOW ERROR
EXIT
