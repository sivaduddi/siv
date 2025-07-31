

PROMPT ------------------------------------------------------------------;
PROMPT $Id$
PROMPT ------------------------------------------------------------------;

exec registration.register ( -
    registration.package_body, -
    upper ('constellation_tool'), -
    '$Id$');

CREATE OR REPLACE TYPE CONSTELLATION_OBJECT FORCE
AS OBJECT (
    CUSTOMER_NO CHAR(12 BYTE),
    CONSTELLATION_ID VARCHAR2(50 BYTE),
    USER_INITIAL CHAR(8 BYTE),
    ACCOUNT_NO CHAR(19 BYTE),
    ACCOUNT_TYPE CHAR(1 BYTE),
    TRADING_PLACE CHAR(1 BYTE),
    NAME VARCHAR2(255 BYTE),
    BOEGA CHAR(1 BYTE),
    KV_PARTICIPIANT_WITHOUT_COST CHAR(1 BYTE),
    INVOICE CHAR(1 BYTE),
    DELIVERY_TRANSACTION CHAR(1 BYTE),
    DELIVERY_KEY CHAR(1 BYTE),
    CUSTODY NUMBER,
    VERWAHRART NUMBER,
    ALLOCATION_TYPE CHAR(1 BYTE),
    SELECTION_CRITERIA_1 VARCHAR2(16),
    SELECTION_VALUE_1 VARCHAR2(255),
    SELECTION_CRITERIA_2 VARCHAR2(16),
    SELECTION_VALUE_2 VARCHAR2(255),
    SELECTION_CRITERIA_3 VARCHAR2(16),
    SELECTION_VALUE_3 VARCHAR2(255),
    LAST_MODIFIED DATE,
    LAST_CHANGE NUMBER,
    IS_ACTIVE CHAR(1 BYTE),
    IS_DEFAULT CHAR(1 BYTE),
    CASH_ACCOUNT_NO CHAR(19 BYTE),
    CACC_CURR CHAR(3 BYTE),
    TEAM_NAME CHAR(20 BYTE),
    ALL_IN_FEE_INDICATOR CHAR(12 BYTE),
    DEVIANT_ACCOUNT_NO CHAR(19 BYTE),
    DEVIANT_CASH_ACCOUNT_NO CHAR(19 BYTE),
    CUSTOMER_LOC_ID NUMBER,
    ROUTING_PATH VARCHAR2(16 BYTE),
    ROUTING_FORMAT VARCHAR2(16 BYTE),
    TECHNICAL_RECEIVER VARCHAR2(255 BYTE),
    USER_INITIAL_1 CHAR(8 BYTE),
    USER_INITIAL_2 CHAR(8 BYTE),
    USER_INITIAL_3 CHAR(8 BYTE),
    ACK CHAR(1 BYTE),
    NACK CHAR(1 BYTE),
    PEND CHAR(1 BYTE),
    EXEC CHAR(1 BYTE),
    INVOICE_CONFIRMATION CHAR(1 BYTE),
    D4D CHAR(1 BYTE),
    EXPIRY CHAR(1 BYTE),
    ALLOC_RPT CHAR(1 BYTE)
);
/

SHOW ERRORS

CREATE OR REPLACE TYPE CONSTELLATION_TABLE AS TABLE OF CONSTELLATION_OBJECT;
/

SHOW ERRORS


CREATE OR REPLACE PACKAGE BODY constellation_tool AS
-- $Id$


/*
 * Get cash account currency for constellation reduction. If exchange is
 * XONTRO but not INVESTRO or XETRA return EUR otherwise return p_currency.
 */
FUNCTION get_cash_account_ccy(
    p_currency  IN      usertype.CURRENCY,
    p_exch      IN      EXCH%ROWTYPE)
RETURN usertype.CURRENCY
IS
BEGIN
    IF    (exchange_tool.is_boss(p_exch) AND p_exch.EXCH_NO <> exchange_tool.exchange_no_investro)
       OR exchange_tool.is_xetra(p_exch)
    THEN RETURN 'EUR';
    ELSE RETURN p_currency;
    END IF;
END get_cash_account_ccy;


/*
 * Select the "best" matching constellation from the given list.
 */
FUNCTION selectConstellation(pThis IN CONSTELLATION_TABLE)
RETURN CONSTELLATION_OBJECT
IS
    v_constellation     CONSTELLATION_OBJECT;
BEGIN
    SELECT *
    INTO   v_constellation
    FROM (
        SELECT CONSTELLATION_OBJECT(
                   CUSTOMER_NO,
                   CONSTELLATION_ID,
                   USER_INITIAL,
                   ACCOUNT_NO,
                   ACCOUNT_TYPE,
                   TRADING_PLACE,
                   NAME,
                   BOEGA,
                   KV_PARTICIPIANT_WITHOUT_COST,
                   INVOICE,
                   DELIVERY_TRANSACTION,
                   DELIVERY_KEY,
                   CUSTODY,
                   VERWAHRART,
                   ALLOCATION_TYPE,
                   SELECTION_CRITERIA_1,
                   SELECTION_VALUE_1,
                   SELECTION_CRITERIA_2,
                   SELECTION_VALUE_2,
                   SELECTION_CRITERIA_3,
                   SELECTION_VALUE_3,
                   LAST_MODIFIED,
                   LAST_CHANGE,
                   IS_ACTIVE,
                   IS_DEFAULT,
                   CASH_ACCOUNT_NO,
                   CACC_CURR,
                   TEAM_NAME,
                   ALL_IN_FEE_INDICATOR,
                   DEVIANT_ACCOUNT_NO,
                   DEVIANT_CASH_ACCOUNT_NO,
                   CUSTOMER_LOC_ID,
                   ROUTING_PATH,
                   ROUTING_FORMAT,
                   TECHNICAL_RECEIVER,
                   USER_INITIAL_1,
                   USER_INITIAL_2,
                   USER_INITIAL_3,
                   ACK,
                   NACK,
                   PEND,
                   EXEC,
                   INVOICE_CONFIRMATION,
                   D4D,
                   EXPIRY,
                   ALLOC_RPT
               )
        FROM   TABLE(CAST(pThis AS CONSTELLATION_TABLE)) t
        ORDER BY
            DECODE(CACC_CURR, 'EUR', 1, 2),     -- Sort EUR account to first position.
            VERWAHRART NULLS LAST,
            CUSTODY    NULLS LAST,
            IS_DEFAULT DESC)
    WHERE ROWNUM = 1;

    RETURN v_constellation;
END selectConstellation;


/*
 * This function converts the given constellation object into a customer LOC
 * rowtype.
 */
FUNCTION toCustomerLOC(pThis IN CONSTELLATION_OBJECT)
RETURN CUSTOMER_LOC%ROWTYPE
IS
    v_customer_loc CUSTOMER_LOC%ROWTYPE;
BEGIN
    v_customer_loc.CUSTOMER_NO          := pThis.CUSTOMER_NO;
    v_customer_loc.CUSTOMER_LOC_ID      := pThis.CUSTOMER_LOC_ID;
    v_customer_loc.ROUTING_PATH         := pThis.ROUTING_PATH;
    v_customer_loc.ROUTING_FORMAT       := pThis.ROUTING_FORMAT;
    v_customer_loc.TECHNICAL_RECEIVER   := pThis.TECHNICAL_RECEIVER;
    v_customer_loc.USER_INITIAL_1       := pThis.USER_INITIAL_1;
    v_customer_loc.USER_INITIAL_2       := pThis.USER_INITIAL_2;
    v_customer_loc.USER_INITIAL_3       := pThis.USER_INITIAL_3;
    v_customer_loc.ACK                  := pThis.ACK;
    v_customer_loc.NACK                 := pThis.NACK;
    v_customer_loc.PEND                 := pThis.PEND;
    v_customer_loc.EXEC                 := pThis.EXEC;
    v_customer_loc.INVOICE_CONFIRMATION := pThis.INVOICE_CONFIRMATION;
    v_customer_loc.D4D                  := pThis.D4D;
    v_customer_loc.EXPIRY               := pThis.EXPIRY;
    v_customer_loc.ALLOC_RPT            := pThis.ALLOC_RPT;

    RETURN v_customer_loc;
END toCustomerLOC;


/*
 * This function converts the given constellation object into a constellation
 * rowtype.
 */
FUNCTION toConstellation(pThis IN CONSTELLATION_OBJECT)
RETURN CONSTELLATION%ROWTYPE
IS
    v_constellation CONSTELLATION%ROWTYPE;
BEGIN
    v_constellation.CUSTOMER_NO                  := pThis.CUSTOMER_NO;
    v_constellation.CONSTELLATION_ID             := pThis.CONSTELLATION_ID;
    v_constellation.USER_INITIAL                 := pThis.USER_INITIAL;
    v_constellation.ACCOUNT_NO                   := pThis.ACCOUNT_NO;
    v_constellation.ACCOUNT_TYPE                 := pThis.ACCOUNT_TYPE;
    v_constellation.TRADING_PLACE                := pThis.TRADING_PLACE;
    v_constellation.NAME                         := pThis.NAME;
    v_constellation.BOEGA                        := pThis.BOEGA;
    v_constellation.KV_PARTICIPIANT_WITHOUT_COST := pThis.KV_PARTICIPIANT_WITHOUT_COST;
    v_constellation.INVOICE                      := pThis.INVOICE;
    v_constellation.DELIVERY_TRANSACTION         := pThis.DELIVERY_TRANSACTION;
    v_constellation.DELIVERY_KEY                 := pThis.DELIVERY_KEY;
    v_constellation.CUSTODY                      := pThis.CUSTODY;
    v_constellation.VERWAHRART                   := pThis.VERWAHRART;
    v_constellation.ALLOCATION_TYPE              := pThis.ALLOCATION_TYPE;
    v_constellation.SELECTION_CRITERIA_1         := pThis.SELECTION_CRITERIA_1;
    v_constellation.SELECTION_VALUE_1            := pThis.SELECTION_VALUE_1;
    v_constellation.SELECTION_CRITERIA_2         := pThis.SELECTION_CRITERIA_2;
    v_constellation.SELECTION_VALUE_2            := pThis.SELECTION_VALUE_2;
    v_constellation.SELECTION_CRITERIA_3         := pThis.SELECTION_CRITERIA_3;
    v_constellation.SELECTION_VALUE_3            := pThis.SELECTION_VALUE_3;
    v_constellation.LAST_MODIFIED                := pThis.LAST_MODIFIED;
    v_constellation.LAST_CHANGE                  := pThis.LAST_CHANGE;
    v_constellation.IS_ACTIVE                    := pThis.IS_ACTIVE;
    v_constellation.IS_DEFAULT                   := pThis.IS_DEFAULT;
    v_constellation.CASH_ACCOUNT_NO              := pThis.CASH_ACCOUNT_NO;
    v_constellation.CACC_CURR                    := pThis.CACC_CURR;
    v_constellation.TEAM_NAME                    := pThis.TEAM_NAME;
    v_constellation.ALL_IN_FEE_INDICATOR         := pThis.ALL_IN_FEE_INDICATOR;
    v_constellation.DEVIANT_ACCOUNT_NO           := pThis.DEVIANT_ACCOUNT_NO;
    v_constellation.DEVIANT_CASH_ACCOUNT_NO      := pThis.DEVIANT_CASH_ACCOUNT_NO;

    RETURN v_constellation;
END toConstellation;


/*
 * Perform acconstellationount/cash account based selection on customer constellations.
 */
FUNCTION base_selection_1(
    p_trading_place     IN            usertype.TRADING_PLACE,
    p_customer_depot_no IN            usertype.ACCOUNT_NO,
    p_cash_account_no   IN            CONSTELLATION.CASH_ACCOUNT_NO%TYPE,
    p_routing_path      IN            CUSTOMER_LOC.ROUTING_PATH%TYPE,
    p_routing_format    IN            CUSTOMER_LOC.ROUTING_FORMAT%TYPE,
    p_custody_type      IN            ORDR.CUSTODY_TYPE%TYPE)
RETURN CONSTELLATION_TABLE
IS
    v_constellations                  CONSTELLATION_TABLE;
BEGIN
    SELECT CONSTELLATION_OBJECT(
               co.CUSTOMER_NO,
               co.CONSTELLATION_ID,
               co.USER_INITIAL,
               co.ACCOUNT_NO,
               co.ACCOUNT_TYPE,
               co.TRADING_PLACE,
               co.NAME,
               co.BOEGA,
               co.KV_PARTICIPIANT_WITHOUT_COST,
               co.INVOICE,
               co.DELIVERY_TRANSACTION,
               co.DELIVERY_KEY,
               co.CUSTODY,
               co.VERWAHRART,
               co.ALLOCATION_TYPE,
               co.SELECTION_CRITERIA_1,
               co.SELECTION_VALUE_1,
               co.SELECTION_CRITERIA_2,
               co.SELECTION_VALUE_2,
               co.SELECTION_CRITERIA_3,
               co.SELECTION_VALUE_3,
               co.LAST_MODIFIED,
               co.LAST_CHANGE,
               co.IS_ACTIVE,
               co.IS_DEFAULT,
               co.CASH_ACCOUNT_NO,
               co.CACC_CURR,
               co.TEAM_NAME,
               co.ALL_IN_FEE_INDICATOR,
               co.DEVIANT_ACCOUNT_NO,
               co.DEVIANT_CASH_ACCOUNT_NO,
               cu.CUSTOMER_LOC_ID,
               cu.ROUTING_PATH,
               cu.ROUTING_FORMAT,
               cu.TECHNICAL_RECEIVER,
               cu.USER_INITIAL_1,
               cu.USER_INITIAL_2,
               cu.USER_INITIAL_3,
               cu.ACK,
               cu.NACK,
               cu.PEND,
               cu.EXEC,
               cu.INVOICE_CONFIRMATION,
               cu.D4D,
               cu.EXPIRY,
               cu.ALLOC_RPT)
    BULK COLLECT INTO v_constellations
    FROM  CONSTELLATION co,
          CONSTELLATION_LOC cl,
          CUSTOMER_LOC cu
    WHERE
      -- Filter on constellation attributes.
          co.TRADING_PLACE                                    = p_trading_place
      AND ( co.ACCOUNT_NO = RPAD(p_customer_depot_no, 19, ' ')
           OR co.DEVIANT_ACCOUNT_NO = RPAD(p_customer_depot_no, 19, ' ')
          )
      AND ( co.CASH_ACCOUNT_NO = RPAD(NVL(p_cash_account_no, co.CASH_ACCOUNT_NO), 19, ' ')
           OR co.DEVIANT_CASH_ACCOUNT_NO = RPAD(NVL(p_cash_account_no, co.CASH_ACCOUNT_NO), 19, ' ')
          )
      AND NVL(co.VERWAHRART, TO_NUMBER(NVL(p_custody_type,'1'))) = TO_NUMBER(NVL(p_custody_type,'1'))
      AND co.IS_ACTIVE                                        = 'Y'
      -- Join for access on customer loc.
      AND cl.CUSTOMER_NO                                      = co.CUSTOMER_NO
      AND cl.CONSTELLATION_ID                                 = co.CONSTELLATION_ID
      AND cu.CUSTOMER_NO                                      = cl.CUSTOMER_NO
      AND cu.CUSTOMER_LOC_ID                                  = cl.CUSTOMER_LOC_ID
      -- Filter on constellation loc attributes.
      AND cu.ROUTING_PATH                                     = NVL(RTRIM(p_routing_path),   cu.ROUTING_PATH)
      AND UPPER(cu.ROUTING_FORMAT)                            = UPPER(NVL(RTRIM(p_routing_format), cu.ROUTING_FORMAT));

    RETURN v_constellations;
END base_selection_1;


/*
 * Perform BIC based selection on customer constellations.
 */
FUNCTION base_selection_2(
    p_technical_receiver IN            CUSTOMER_LOC.TECHNICAL_RECEIVER%TYPE,
    p_trading_place      IN            usertype.TRADING_PLACE,
    p_routing_path       IN            CUSTOMER_LOC.ROUTING_PATH%TYPE,
    p_routing_format     IN            CUSTOMER_LOC.ROUTING_FORMAT%TYPE,
    p_custody_type       IN            ORDR.CUSTODY_TYPE%TYPE)
RETURN CONSTELLATION_TABLE
IS
    v_constellations                   CONSTELLATION_TABLE;
BEGIN
    SELECT CONSTELLATION_OBJECT(
               co.CUSTOMER_NO,
               co.CONSTELLATION_ID,
               co.USER_INITIAL,
               co.ACCOUNT_NO,
               co.ACCOUNT_TYPE,
               co.TRADING_PLACE,
               co.NAME,
               co.BOEGA,
               co.KV_PARTICIPIANT_WITHOUT_COST,
               co.INVOICE,
               co.DELIVERY_TRANSACTION,
               co.DELIVERY_KEY,
               co.CUSTODY,
               co.VERWAHRART,
               co.ALLOCATION_TYPE,
               co.SELECTION_CRITERIA_1,
               co.SELECTION_VALUE_1,
               co.SELECTION_CRITERIA_2,
               co.SELECTION_VALUE_2,
               co.SELECTION_CRITERIA_3,
               co.SELECTION_VALUE_3,
               co.LAST_MODIFIED,
               co.LAST_CHANGE,
               co.IS_ACTIVE,
               co.IS_DEFAULT,
               co.CASH_ACCOUNT_NO,
               co.CACC_CURR,
               co.TEAM_NAME,
               co.ALL_IN_FEE_INDICATOR,
               co.DEVIANT_ACCOUNT_NO,
               co.DEVIANT_CASH_ACCOUNT_NO,
               cu.CUSTOMER_LOC_ID,
               cu.ROUTING_PATH,
               cu.ROUTING_FORMAT,
               cu.TECHNICAL_RECEIVER,
               cu.USER_INITIAL_1,
               cu.USER_INITIAL_2,
               cu.USER_INITIAL_3,
               cu.ACK,
               cu.NACK,
               cu.PEND,
               cu.EXEC,
               cu.INVOICE_CONFIRMATION,
               cu.D4D,
               cu.EXPIRY,
               cu.ALLOC_RPT)
    BULK COLLECT INTO v_constellations
    FROM  CUSTOMERS c,
          CONSTELLATION co,
          CONSTELLATION_LOC cl,
          CUSTOMER_LOC cu
    WHERE
      -- Filter on BIC.
          c.BIC                                         = SUBSTR(p_technical_receiver, 1, 8)
      -- Join constellations.
      AND co.CUSTOMER_NO                                = c.CUSTOMER_NO
      -- Filter on constellations.
      AND co.TRADING_PLACE                              = p_trading_place
      AND NVL(co.VERWAHRART, TO_NUMBER(NVL(p_custody_type,'1'))) = TO_NUMBER(NVL(p_custody_type,'1'))
      AND co.IS_ACTIVE                                  = 'Y'
      -- Join customer loc.
      AND cl.CUSTOMER_NO                                = co.CUSTOMER_NO
      AND cl.CONSTELLATION_ID                           = co.CONSTELLATION_ID
      AND cu.CUSTOMER_NO                                = cl.CUSTOMER_NO
      AND cu.CUSTOMER_LOC_ID                            = cl.CUSTOMER_LOC_ID
      -- Filter on routing path.
      AND cu.ROUTING_PATH                               =       RTRIM(p_routing_path)
      AND UPPER(cu.ROUTING_FORMAT)                      = UPPER(RTRIM(p_routing_format));

    RETURN v_constellations;
END base_selection_2;


FUNCTION base_selection_3(
    p_sid                IN            CUSTOMERS.SID%TYPE,
    p_trading_place      IN            usertype.TRADING_PLACE,
    p_routing_path       IN            CUSTOMER_LOC.ROUTING_PATH%TYPE,
    p_routing_format     IN            CUSTOMER_LOC.ROUTING_FORMAT%TYPE,
    p_technical_receiver IN            CUSTOMER_LOC.TECHNICAL_RECEIVER%TYPE,
    p_custody_type       IN            ORDR.CUSTODY_TYPE%TYPE,
    p_order_if_account   IN            ORDR_IF.ACCOUNT%TYPE,
    p_exch               IN            EXCH%ROWTYPE)
RETURN CONSTELLATION_TABLE
IS
    v_constellations                   CONSTELLATION_TABLE;
    v_technical_receiver               CUSTOMER_LOC.TECHNICAL_RECEIVER%TYPE := NULL;
BEGIN
    SELECT CONSTELLATION_OBJECT(
               co.CUSTOMER_NO,
               co.CONSTELLATION_ID,
               co.USER_INITIAL,
               co.ACCOUNT_NO,
               co.ACCOUNT_TYPE,
               co.TRADING_PLACE,
               co.NAME,
               co.BOEGA,
               co.KV_PARTICIPIANT_WITHOUT_COST,
               co.INVOICE,
               co.DELIVERY_TRANSACTION,
               co.DELIVERY_KEY,
               co.CUSTODY,
               co.VERWAHRART,
               co.ALLOCATION_TYPE,
               co.SELECTION_CRITERIA_1,
               co.SELECTION_VALUE_1,
               co.SELECTION_CRITERIA_2,
               co.SELECTION_VALUE_2,
               co.SELECTION_CRITERIA_3,
               co.SELECTION_VALUE_3,
               co.LAST_MODIFIED,
               co.LAST_CHANGE,
               co.IS_ACTIVE,
               co.IS_DEFAULT,
               co.CASH_ACCOUNT_NO,
               co.CACC_CURR,
               co.TEAM_NAME,
               co.ALL_IN_FEE_INDICATOR,
               co.DEVIANT_ACCOUNT_NO,
               co.DEVIANT_CASH_ACCOUNT_NO,
               cu.CUSTOMER_LOC_ID,
               cu.ROUTING_PATH,
               cu.ROUTING_FORMAT,
               cu.TECHNICAL_RECEIVER,
               cu.USER_INITIAL_1,
               cu.USER_INITIAL_2,
               cu.USER_INITIAL_3,
               cu.ACK,
               cu.NACK,
               cu.PEND,
               cu.EXEC,
               cu.INVOICE_CONFIRMATION,
               cu.D4D,
               cu.EXPIRY,
               cu.ALLOC_RPT)
    BULK COLLECT INTO v_constellations
    FROM  CUSTOMERS c,
          CONSTELLATION co,
          CONSTELLATION_LOC cl,
          CUSTOMER_LOC cu
    WHERE
      -- Filter on SID.
          NVL(c.SID, '-')                               = NVL(p_sid, NVL(c.SID, '-'))
      -- Join constellations.
      AND co.CUSTOMER_NO                                = c.CUSTOMER_NO
      -- Filter on constellations.
      AND co.TRADING_PLACE                              = p_trading_place
      AND NVL(co.VERWAHRART, TO_NUMBER(NVL(p_custody_type,'1'))) = TO_NUMBER(NVL(p_custody_type,'1'))
      AND co.IS_ACTIVE                                  = 'Y'
      -- Join customer loc.
      AND cl.CUSTOMER_NO                                = co.CUSTOMER_NO
      AND cl.CONSTELLATION_ID                           = co.CONSTELLATION_ID
      AND cu.CUSTOMER_NO                                = cl.CUSTOMER_NO
      AND cu.CUSTOMER_LOC_ID                            = cl.CUSTOMER_LOC_ID
      -- Filter on routing path and technical receiver.
      AND cu.ROUTING_PATH                               = RTRIM(p_routing_path)
      AND (   p_technical_receiver IS NULL
           OR

              REGEXP_LIKE(RTRIM(p_technical_receiver), cu.TECHNICAL_RECEIVER)
           OR (
                   p_exch.MIC IS NOT NULL
               AND REGEXP_LIKE(RTRIM(p_technical_receiver) || '/' || RTRIM(p_exch.MIC),cu.TECHNICAL_RECEIVER)
              )
           )
      AND (
              co.CONSTELLATION_GROUP       = NVL(p_order_if_account,co.CONSTELLATION_GROUP)
           OR RTRIM(co.ACCOUNT_NO)         = NVL(p_order_if_account,RTRIM(co.ACCOUNT_NO))
           OR RTRIM(co.DEVIANT_ACCOUNT_NO) = NVL(p_order_if_account,RTRIM(co.DEVIANT_ACCOUNT_NO))
          );


    RETURN v_constellations;
END base_selection_3;


FUNCTION get_customer_boega_by_account(
    p_customer_no            IN     CONSTELLATION.CUSTOMER_NO%TYPE,
    p_account_no             IN     CONSTELLATION.ACCOUNT_NO%TYPE,
    p_account_type           IN     CONSTELLATION.ACCOUNT_TYPE%TYPE)
RETURN CHAR
IS
    v_boega                         CONSTELLATION.BOEGA%TYPE;
BEGIN
    SELECT boega
      INTO v_boega
      FROM CONSTELLATION
     WHERE CUSTOMER_NO  = p_customer_no
       AND ACCOUNT_NO   = p_account_no
       AND ACCOUNT_TYPE = p_account_type;

   RETURN v_boega;

EXCEPTION WHEN NO_DATA_FOUND
THEN RETURN NULL;
END  get_customer_boega_by_account;


/*
 * This procedure checks if p_order should have a constellation
 * set. If it is not set but account, cash account and
 * trading place are defined the procedure tries
 * to get a default constellation for the order.
 */
FUNCTION get_default_constellation( -- (1)
    p_account_no        IN usertype.ACCOUNT_NO,
    p_cash_account_no   IN usertype.ACCOUNT_NO,
    p_cacc_curr         IN usertype.CURRENCY,
    p_trading_place     IN usertype.TRADING_PLACE)
RETURN CONSTELLATION%ROWTYPE
IS
    CURSOR c_constellation(
        p_account_no          IN usertype.ACCOUNT_NO,
        p_cash_account_no     IN usertype.ACCOUNT_NO,
        p_cacc_curr           IN usertype.CURRENCY,
        p_trading_place       IN usertype.TRADING_PLACE)
    IS
        SELECT *
        FROM   CONSTELLATION
        WHERE  NVL(DEVIANT_ACCOUNT_NO, ACCOUNT_NO)           = RPAD(p_account_no,      19, ' ')
           AND NVL(DEVIANT_CASH_ACCOUNT_NO, CASH_ACCOUNT_NO) = RPAD(p_cash_account_no, 19, ' ')
           AND CACC_CURR                                     = p_cacc_curr
           AND TRADING_PLACE                                 = p_trading_place
           AND IS_ACTIVE                                     = 'Y'
        ORDER BY IS_DEFAULT DESC; -- default = 'Y' has highest precedence

    v_constellation CONSTELLATION%ROWTYPE;

BEGIN
    OPEN c_constellation(
        p_account_no,
        p_cash_account_no,
        p_cacc_curr,
        p_trading_place);

    FETCH c_constellation
    INTO  v_constellation;

    CLOSE c_constellation;

    RETURN v_constellation;
END get_default_constellation;

/*
 * Get default constellation record for given customer and trading place.
 */
FUNCTION get_default_constellation( -- (2)
    p_customer_no       IN  CUSTOMERS.CUSTOMER_NO%TYPE,
    p_trading_place     IN  MARKET.TRADING_PLACE%TYPE)
RETURN CONSTELLATION%ROWTYPE
IS
    v_constellation  CONSTELLATION%ROWTYPE;
BEGIN
    BEGIN
        SELECT *
        INTO   v_constellation
        FROM   CONSTELLATION
        WHERE  CUSTOMER_NO         = p_customer_no
           AND TRADING_PLACE       = p_trading_place
           AND IS_DEFAULT          = 'Y'
           AND IS_ACTIVE           = 'Y';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END;

    RETURN v_constellation;
END get_default_constellation;


/*
 * This procedure determines the constellation of stop orders.
 */
PROCEDURE get_constellation_stop_order(
    p_trading_place      IN            usertype.TRADING_PLACE,
    p_routing_path       IN            CUSTOMER_LOC.ROUTING_PATH%TYPE,
    p_routing_format     IN            CUSTOMER_LOC.ROUTING_FORMAT%TYPE,
    p_technical_receiver IN            CUSTOMER_LOC.TECHNICAL_RECEIVER%TYPE,
    p_sid                IN            CUSTOMERS.SID%TYPE                       := NULL,
    p_custody_type       IN            ORDR.CUSTODY_TYPE%TYPE,
    p_custody            IN            ORDR.CUSTODY%TYPE,
    p_customer_depot_no  IN            usertype.ACCOUNT_NO,
    p_cash_account_no    IN            CONSTELLATION.CASH_ACCOUNT_NO%TYPE,
    p_cash_account_ccy   IN            usertype.CURRENCY,
    p_cust_settl_info    IN            VARCHAR2 := NULL,
    p_order_if_account   IN            ORDR_IF.ACCOUNT%TYPE := NULL,
    p_exch               IN            EXCH%ROWTYPE,
    p_strict             IN            BOOLEAN := TRUE,
    p_constellation         OUT NOCOPY CONSTELLATION%ROWTYPE,
    p_customer_loc          OUT NOCOPY CUSTOMER_LOC%ROWTYPE)
IS
    v_constellations                   CONSTELLATION_TABLE;
    v_constellation                    CONSTELLATION_OBJECT;
    v_iteration                        BINARY_INTEGER    := 0;
    v_cash_account_ccy                 usertype.CURRENCY := p_cash_account_ccy;
    v_custody                          INTEGER           := TO_NUMBER(p_custody);
    v_selection_value_set              VARCHAR2(32000)   := CHR(10);
    v_selection_value                  VARCHAR2(255);
    v_start                            BINARY_INTEGER    :=  0;
    v_length                           BINARY_INTEGER    :=  0;

    v_i                                BINARY_INTEGER;
    v_next                             BINARY_INTEGER;

BEGIN
    /*
     * Base selection, the result set might contain too many rows. If it is empty
     * definitely no constellation will be found. If the set contains excatly one
     * row we are done with success. If there is more than row additional filtering
     * is applied in order to reduce the set. If additional filtering results in
     * more than one row the first member of the set is returned.
     */
    IF p_customer_depot_no IS NOT NULL
    THEN v_constellations := base_selection_1(
                                 p_trading_place     => p_trading_place,
                                 p_customer_depot_no => p_customer_depot_no,
                                 p_cash_account_no   => p_cash_account_no,
                                 p_routing_path      => p_routing_path,
                                 p_routing_format    => p_routing_format,
                                 p_custody_type      => p_custody_type);
    ELSE
        -- As no Sender ID is given p_technical_receiver contains a BIC code (SWIFT order)
        IF p_sid IS NULL AND p_order_if_account IS NULL
        THEN v_constellations := base_selection_2(
                                     p_technical_receiver => p_technical_receiver,
                                     p_trading_place      => p_trading_place,
                                     p_routing_path       => p_routing_path,
                                     p_routing_format     => p_routing_format,
                                     p_custody_type       => p_custody_type);
        ELSE v_constellations := base_selection_3(
                                     p_sid                => p_sid,
                                     p_trading_place      => p_trading_place,
                                     p_routing_path       => p_routing_path,
                                     p_routing_format     => p_routing_format,
                                     p_technical_receiver => p_technical_receiver,
                                     p_custody_type       => p_custody_type,
                                     p_order_if_account   => p_order_if_account,
                                     p_exch               => p_exch);
        END IF;
    END IF;

    /*
     * Even most relaxed condition does not return any row. This is an error.
     */
    IF v_constellations.COUNT = 0
    THEN
        IF p_strict
        THEN
            RAISE_APPLICATION_ERROR(
                error.application_error_no,
                error.format(
                   error.select_failed,
                   userobject.get_description (
                       userobject.table_code,
                       'CONSTELLATION'),
                   error.format(
                       error.not_exists,
                       format.compound_key(
                           p_technical_receiver,
                           p_trading_place,
                           RTRIM(p_customer_depot_no),
                           RTRIM(p_cash_account_no),
                           RTRIM(p_routing_path),
                           RTRIM(p_routing_format),
                           p_custody_type,
                           RTRIM(p_order_if_account)
                       )
                    )
               )
            );
        ELSE
            RETURN;
        END IF;
    END IF;

    /*
     * Backup leading constellation as reduction might remove all constellations.
     */
    v_constellation := selectConstellation(v_constellations);

    /*
     * Further reduction is required. Therefor cash account currency is required.
     */
    IF v_constellations.COUNT > 1
    THEN v_cash_account_ccy := get_cash_account_ccy(v_cash_account_ccy, p_exch);
    END IF;

    /*
     * Now try to find first matching configuration.
     */
    <<outer>>
    WHILE v_constellations.COUNT > 1 AND v_iteration < 3
    LOOP
        v_iteration := v_iteration + 1;

        /*
         * Skip non-selective filters.
         */
        -- Settlement currency.
        IF     v_iteration = 1
           AND (
                -- Skip if account/cash account is given.
                   (
                        p_customer_depot_no IS NOT NULL
                    AND p_cash_account_no   IS NOT NULL
                   )
                -- Skip if no settlement currency is given.
                OR v_cash_account_ccy IS NULL
               )
        THEN v_iteration := v_iteration + 1;
        END IF;

        -- Custody.
        IF     v_iteration = 2
           -- Skip if no custody is given.
           AND v_custody IS NULL
        THEN v_iteration := v_iteration + 1;
        END IF;

        -- LAKOST
        IF v_iteration = 3
        THEN
            -- Skip if no parameters are given.
            IF p_cust_settl_info IS NULL
            THEN v_iteration := v_iteration + 1;

            -- Else prepare LAKOST parameters for matching.
            ELSE
                WHILE v_length >= 0
                LOOP
                    v_start  := v_start + v_length + 1;
                    v_length := INSTR(p_cust_settl_info, ';' , v_start, 1) - v_start;

                    IF v_length > 0
                    THEN v_selection_value := SUBSTR(p_cust_settl_info, v_start, v_length);
                    ELSE
                        v_selection_value := SUBSTR(p_cust_settl_info, v_start);
                        v_length          := -1; -- end loop
                    END IF;

                    v_selection_value_set :=    v_selection_value_set
                                             || RPAD(LTRIM(v_selection_value, '0'), 15, 'X')
                                             || CHR(10);
                END LOOP;
            END IF;
        END IF;

        /*
         * Apply current filter to all constellations selected in by base_selection.
         */
        v_i := v_constellations.FIRST;
        LOOP
            EXIT WHEN v_i IS NULL OR v_iteration > 3;
            v_next := v_constellations.NEXT(v_i);

            CASE v_iteration
                -- -------------------------------
                -- Match settlement currency.
                -- -------------------------------
                WHEN 1
                THEN
                    IF NOT (NVL(v_constellations(v_i).CACC_CURR, p_cash_account_ccy) = p_cash_account_ccy)
                    THEN v_constellations.DELETE(v_i);
                    END IF;

                -- -------------------------------
                -- Match custody.
                -- -------------------------------
                WHEN 2
                THEN
                    IF   NOT(NVL(v_constellations(v_i).CUSTODY, v_custody) = v_custody)
                    THEN v_constellations.DELETE(v_i);
                    END IF;

                -- -------------------------------
                -- Match LAKOST parameters.
                -- -------------------------------
                WHEN 3
                THEN
                    -- No LAKOST parameter has been passed in, done.
                    IF v_selection_value_set = CHR(10)
                    THEN EXIT outer;
                    END IF;

                    IF     (   RTRIM(v_constellations(v_i).SELECTION_VALUE_1) IS NOT NULL
                            OR RTRIM(v_constellations(v_i).SELECTION_VALUE_2) IS NOT NULL
                            OR RTRIM(v_constellations(v_i).SELECTION_VALUE_3) IS NOT NULL
                           )
                       AND INSTR(
                               v_selection_value_set,
                               RPAD(LTRIM(v_constellations(v_i).SELECTION_VALUE_1, '0'), 15, 'X')
                               || CHR(10)
                           ) > 0
                       AND INSTR(
                               v_selection_value_set,
                               RPAD(LTRIM(v_constellations(v_i).SELECTION_VALUE_2, '0'), 15, 'X')
                               || CHR(10)
                           ) > 0
                       AND INSTR(
                               v_selection_value_set,
                               RPAD(LTRIM(v_constellations(v_i).SELECTION_VALUE_3, '0'), 15, 'X')
                               || CHR(10)
                           ) > 0
                    THEN EXIT outer;
                    END IF;

                    v_constellations.DELETE(v_i);

                -- Just to make sure that we are not running out of bounds.
                ELSE NULL;
            END CASE;

            v_i := v_next;
        END LOOP;
    END LOOP;

    /*
     * If additional filtering has removed all constellations take first one
     * that has been found by relaxed filter.
     */
    IF v_constellations.COUNT > 0 AND v_iteration > 0
    THEN v_constellation := selectConstellation(v_constellations);
    END IF;

    p_constellation := toConstellation(v_constellation);
    p_customer_loc  := toCustomerLOC  (v_constellation);
END get_constellation_stop_order;


/*
 * This procedure determines the constellation of trust orders.
 */
PROCEDURE get_constellation_trust_order(
    p_trading_place      IN            usertype.TRADING_PLACE,
    p_customer_depot_no  IN            usertype.ACCOUNT_NO,
    p_cash_account_ccy   IN            usertype.CURRENCY,
    p_custody_type       IN            ORDR.CUSTODY_TYPE%TYPE,
    p_custody            IN            ORDR.CUSTODY%TYPE,
    p_exch               IN            EXCH%ROWTYPE,
    p_constellation         OUT NOCOPY CONSTELLATION%ROWTYPE)
IS
    v_customer_loc                     CUSTOMER_LOC%ROWTYPE;
BEGIN
    get_constellation_stop_order(
        p_trading_place         => p_trading_place,
        p_routing_path          => NULL,
        p_routing_format        => NULL,
        p_technical_receiver    => NULL,
        p_custody_type          => p_custody_type,
        p_custody               => p_custody,
        p_customer_depot_no     => p_customer_depot_no,
        p_cash_account_no       => NULL,
        p_cash_account_ccy      => p_cash_account_ccy,
        p_cust_settl_info       => NULL,
        p_exch                  => p_exch,
        p_constellation         => p_constellation,
        p_customer_loc          => v_customer_loc);
END get_constellation_trust_order;


/*
 * This procedure determines the constellation for gateways RORS and ORCS.
 */
PROCEDURE get_constellation_hvb_s_side(
    p_sid                IN            CUSTOMERS.SID%TYPE,
    p_trading_place      IN            usertype.TRADING_PLACE,
    p_routing_path       IN            CUSTOMER_LOC.ROUTING_PATH%TYPE,
    p_technical_receiver IN            CUSTOMER_LOC.TECHNICAL_RECEIVER%TYPE,
    p_exch               IN            EXCH%ROWTYPE,
    p_custody_type       IN            ORDR.CUSTODY_TYPE%TYPE,
    p_cash_account_ccy   IN            usertype.CURRENCY,
    p_custody            IN            ORDR.CUSTODY%TYPE,
    p_cust_settl_info    IN            VARCHAR2,
    p_constellation         OUT NOCOPY CONSTELLATION%ROWTYPE)
IS
    v_customer_loc                     CUSTOMER_LOC%ROWTYPE;
BEGIN
    get_constellation_stop_order(
        p_trading_place         => p_trading_place,
        p_routing_path          => p_routing_path,
        p_routing_format        => NULL,
        p_technical_receiver    => p_technical_receiver,
        p_sid                   => p_sid,
        p_custody_type          => p_custody_type,
        p_custody               => p_custody,
        p_customer_depot_no     => NULL,
        p_cash_account_no       => NULL,
        p_cash_account_ccy      => p_cash_account_ccy,
        p_cust_settl_info       => p_cust_settl_info,
        p_exch                  => p_exch,
        p_constellation         => p_constellation,
        p_customer_loc          => v_customer_loc);
END get_constellation_hvb_s_side;


/*
 * This procedures gets all LOCs for a customer constellation. The result set may
 * be restricted by an optional routing format. In this case ony LOCs with the
 * requested routing format are returned.
 */
PROCEDURE get_loc(
    p_customer_no       IN      CUSTOMERS.CUSTOMER_NO%TYPE,
    p_constellation_id  IN      CONSTELLATION.CONSTELLATION_ID%TYPE,
    p_routing_format    IN      ROUTING_PATHS.ROUTING_FORMAT%TYPE := NULL,
    p_loc               OUT     usertype.REF_CURSOR)
IS
BEGIN
    OPEN p_loc
    FOR
        SELECT CUSTOMER_NO,
               CUSTOMER_LOC_ID,
               culoc.ROUTING_PATH,
               culoc.ROUTING_FORMAT,
               culoc.TECHNICAL_RECEIVER,
               culoc.USER_INITIAL_1,
               culoc.USER_INITIAL_2,
               culoc.USER_INITIAL_3,
               culoc.ACK,
               culoc.NACK,
               culoc.PEND,
               culoc.EXEC,
               culoc.INVOICE_CONFIRMATION,
               culoc.D4D,
               culoc.EXPIRY,
               culoc.ALLOC_RPT
        FROM   CONSTELLATION_LOC coloc NATURAL INNER JOIN CUSTOMER_LOC culoc
        WHERE  CUSTOMER_NO          = p_customer_no
           AND CONSTELLATION_ID     = p_constellation_id
           AND culoc.ROUTING_FORMAT = NVL(p_routing_format, culoc.ROUTING_FORMAT);
END get_loc;

/*
 * This procedures gets one specific(first) LOC of a customer constellation.
 */
PROCEDURE get_customer_loc(
    p_customer_no      IN       CUSTOMERS.CUSTOMER_NO%TYPE,
    p_constellation_id IN       CONSTELLATION.CONSTELLATION_ID%TYPE,
    p_routing_format   IN       ORDR_IF.ROUTING_FORMAT%TYPE,
    p_customer_loc     OUT      CUSTOMER_LOC%ROWTYPE
)
IS
    v_loc  usertype.REF_CURSOR;
BEGIN
    get_loc(
        p_customer_no       => p_customer_no,
        p_constellation_id  => p_constellation_id,
        p_routing_format    => p_routing_format,
        p_loc               => v_loc
    );

    FETCH v_loc into p_customer_loc;

    CLOSE v_loc;

END get_customer_loc;

/*
 * Get exchange key from constellation for routing path 'XONTRO'
 */
FUNCTION get_xontro_loc(
    p_order       IN      ORDR%ROWTYPE)
RETURN usertype.EXCH_KEY
IS
    v_exch_no  usertype.EXCH_NO;
    v_exch_key usertype.EXCH_KEY;
BEGIN
    BEGIN
        SELECT culoc.TECHNICAL_RECEIVER
        INTO   v_exch_no
        FROM   CONSTELLATION_LOC coloc NATURAL INNER JOIN CUSTOMER_LOC culoc
        WHERE  CUSTOMER_NO         = p_order.CUSTOMER_NO
           AND CONSTELLATION_ID    = p_order.CONSTELLATION_ID
           AND culoc.ROUTING_PATH  = 'XONTRO';
    EXCEPTION
        WHEN NO_DATA_FOUND THEN RETURN NULL;
    END;

    v_exch_key := exchange_tool.get_exchange_key_by_no(
        SUBSTR(TRIM(v_exch_no), 1, 3), 'Y', 'N');

    IF v_exch_key IS NULL
    THEN
        sp_interface_error_entry (
            p_log_process       => 'INVOICE',
            p_log_timestamp     =>
                xml_convert_func.sp_date_time_for_xml(sysdate),
            p_log_msg_direction => 'OUT',
            p_log_msg_type      => 'INVOICE',
            p_log_error_type    => '50',
            p_log_error_reason  =>
                error.format(
                    error.invalid_xontro_path,
                    p_order.CUSTOMER_NO,
                    p_order.CONSTELLATION_ID),
            p_log_error_no      => NULL,
            p_log_instrument    => SUBSTR(p_order.WKN, 7),
            p_log_ext_order_no  => p_order.HVB_ORDER_NUMBER,
            p_log_best_order_no => p_order.ORDER_NO);
    END IF;

    RETURN v_exch_key;

END get_xontro_loc;

/*
 * Get best fitting constellation for given invoice record if there is one
 */
PROCEDURE constellation_reverse_lookup(
    p_invoice       IN OUT NOCOPY  INVOICE%ROWTYPE,
    p_orig_invoice  IN             INVOICE%ROWTYPE)
IS
    v_weight_1                     INTEGER;
    v_constellation_id_1           CONSTELLATION.CONSTELLATION_ID%TYPE;
    v_customer_no_1                CONSTELLATION.CUSTOMER_NO%TYPE;
    v_weight_2                     INTEGER;
    v_constellation_id_2           CONSTELLATION.CONSTELLATION_ID%TYPE;
    v_customer_no_2                CONSTELLATION.CUSTOMER_NO%TYPE;
    v_deviant_account_no_1         usertype.ACCOUNT_NO;
    v_deviant_cash_account_no_1    usertype.ACCOUNT_NO;
    v_deviant_account_no_2         usertype.ACCOUNT_NO;
    v_deviant_cash_account_no_2    usertype.ACCOUNT_NO;

    CURSOR crs_weighted_constellations IS
        SELECT
            CUSTOMER_NO,
            CONSTELLATION_ID,
            DEVIANT_ACCOUNT_NO,
            DEVIANT_CASH_ACCOUNT_NO,
            CASE
                WHEN   RTRIM(CUSTOMER_NO)           || CONSTELLATION_ID
                     = RTRIM(p_invoice.CUSTOMER_NO) || p_invoice.CONSTELLATION_ID
                THEN 22
                ELSE  0
            END
          + CASE
                WHEN ALLOCATION_TYPE IS NULL                   THEN 1
                WHEN ALLOCATION_TYPE = p_invoice.CHARGING_TYPE THEN 2
                ELSE                                               -1
            END
          + CASE
                WHEN VERWAHRART IS NULL                        THEN 1
                WHEN VERWAHRART = p_invoice.CUSTODY_TYPE       THEN 2
                ELSE                                               -1
            END
          + CASE
                WHEN CUSTODY IS NULL                           THEN 1
                WHEN CUSTODY = p_invoice.CUSTODY               THEN 2
                ELSE                                               -1
            END
          + CASE
                WHEN BOEGA = p_invoice.BOEGA                   THEN 2
                ELSE                                               -1
            END
          + CASE
                WHEN TRADING_PLACE = p_invoice.TRADING_PLACE   THEN 9
                ELSE                                                0
            END AS "W"
    FROM  CONSTELLATION
    WHERE ACCOUNT_NO      = p_invoice.ACCOUNT_NO
    AND   CASH_ACCOUNT_NO = p_invoice.CASH_ACCOUNT_NO
    AND   CACC_CURR       = p_invoice.CACC_CURR
    AND   IS_ACTIVE       = 'Y'
    ORDER BY "W" DESC;

BEGIN
    --
    -- Only customer bookings do have a constellation.
    --
    IF     p_invoice.TRANSACTION_TYPE = 'A'
       AND p_invoice.NOSTRO           = 'N'
    THEN
        OPEN crs_weighted_constellations;

        FETCH crs_weighted_constellations
        INTO  v_customer_no_1,
              v_constellation_id_1,
              v_deviant_account_no_1,
              v_deviant_cash_account_no_1,
              v_weight_1;

        IF crs_weighted_constellations%NOTFOUND
        THEN
           p_invoice.CUSTOMER_NO      := NULL;
           p_invoice.CONSTELLATION_ID := NULL;
        ELSE
            FETCH crs_weighted_constellations
            INTO  v_customer_no_2,
                  v_constellation_id_2,
                  v_deviant_account_no_2,
                  v_deviant_cash_account_no_2,
                  v_weight_2;

            IF crs_weighted_constellations%NOTFOUND
            OR v_weight_1 > v_weight_2
            THEN
                p_invoice.CUSTOMER_NO             := v_customer_no_1;
                p_invoice.CONSTELLATION_ID        := v_constellation_id_1;
                p_invoice.DEVIANT_ACCOUNT_NO      := v_deviant_account_no_1;
                p_invoice.DEVIANT_CASH_ACCOUNT_NO := v_deviant_cash_account_no_1;

            ELSE
                p_invoice.CUSTOMER_NO             := NULL;
                p_invoice.CONSTELLATION_ID        := NULL;
                p_invoice.DEVIANT_ACCOUNT_NO      := NULL;
                p_invoice.DEVIANT_CASH_ACCOUNT_NO := NULL;

            END IF;
        END IF;

        CLOSE crs_weighted_constellations;

        --
        -- A matching constellation doesn't need to exist, if cash_account_no
        -- contains the cash account of custody (charging type against foreign).
        -- In this case do not change constellation, if account and cash account
        -- are unchanged.
        --
        IF     p_invoice.CUSTOMER_NO     IS NULL
           AND p_invoice.ACCOUNT_NO      =  p_orig_invoice.ACCOUNT_NO
           AND p_invoice.CASH_ACCOUNT_NO =  p_orig_invoice.CASH_ACCOUNT_NO
           AND p_invoice.CACC_CURR       =  p_orig_invoice.CACC_CURR
        THEN
            p_invoice.CUSTOMER_NO      := p_orig_invoice.CUSTOMER_NO;
            p_invoice.CONSTELLATION_ID := p_orig_invoice.CONSTELLATION_ID;
        END IF;
    END IF;
END constellation_reverse_lookup;

END constellation_tool;
/

SHOW ERRORS
EXIT
