/*
** -----------------------------------------------------------------------
** The package calvin provides functionality for communications with the
** KORDOBA backoffice via Calvin interface (library libCalvinQuery).
**
** The following functionalities are supported:
**
** tan validation,
** underlying-stock query,
** underlying-stock lock/release,
** account balance query,
** account transfer,
** SEPA cash transfer
** authentication,
** session tan activation,
** session tan deactivation,
** create session token,
** login
** logout
**
** -----------------------------------------------------------------------
*/

PROMPT ------------------------------------------------------------------;
PROMPT $Id$
PROMPT ------------------------------------------------------------------;


exec registration.register ( -
    registration.package_body, -
    upper ('calvin'), -
    '$Id$');

CREATE OR REPLACE PACKAGE BODY calvin
AS
    -- $Id$

    /*
    ** internal constants
    */
    c_log_file           CONSTANT VARCHAR2(12) := 'calvin.log';
    c_text_calvin_error  CONSTANT VARCHAR2(14) := 'ERROR. ';
    c_text_request       CONSTANT VARCHAR2(15) := 'Request data:  ';
    c_text_response      CONSTANT VARCHAR2(15) := 'Response data: ';
    c_text_description   CONSTANT VARCHAR2(15) := 'Description:   ';
    c_xml_header         CONSTANT VARCHAR2(38) := '<?xml version="1.0" encoding="UTF-8"?>';

    ATTR_ERROR_CODE      CONSTANT VARCHAR2(09) := 'errorcode';
    ATTR_ERROR_DESC      CONSTANT VARCHAR2(09) := 'errordesc';
    ATTR_ERROR_ORIG      CONSTANT VARCHAR2(09) := 'errororig';
    ATTR_SESSION_ID      CONSTANT VARCHAR2(09) := 'sessionid';
    ATTR_LANGUAGE        CONSTANT VARCHAR2(08) := 'language';
    ATTR_FEID            CONSTANT VARCHAR2(04) := 'feid';

    /*
    ** HTTP stuff derived from the old CPP interface
    */
    HTTP_PROTO           CONSTANT VARCHAR2(4)  := 'http';
    SLASH                CONSTANT VARCHAR2(2)  := '/';
    DEFAULT_HTTP_PORT    CONSTANT VARCHAR2(2)  := '80';

    /* Request header fields
    */
    HF_ALLOW             CONSTANT VARCHAR2(05) := 'Allow';
    HF_AUTHORIZATION     CONSTANT VARCHAR2(13) := 'Authorization';
    HF_CONTENT_ENCODING  CONSTANT VARCHAR2(16) := 'Content-Encoding';
    HF_CONTENT_LENGTH    CONSTANT VARCHAR2(14) := 'Content-Length';
    HF_CONTENT_TYPE      CONSTANT VARCHAR2(12) := 'Content-Type';
    HF_DATE              CONSTANT VARCHAR2(04) := 'Date';
    HF_EXPIRES           CONSTANT VARCHAR2(07) := 'Expires';
    HF_FROM              CONSTANT VARCHAR2(04) := 'From';
    HF_IF_MODIFIED_SINCE CONSTANT VARCHAR2(17) := 'If-Modified-Since';
    HF_LAST_MODIFIED     CONSTANT VARCHAR2(13) := 'Last-Modified';
    HF_LOCATION          CONSTANT VARCHAR2(08) := 'Location';
    HF_MIME_VERSION      CONSTANT VARCHAR2(12) := 'MIME-Version';
    HF_PRAGMA            CONSTANT VARCHAR2(06) := 'Pragma';
    HF_REFERER           CONSTANT VARCHAR2(07) := 'Referer';
    HF_SERVER            CONSTANT VARCHAR2(06) := 'Server';
    HF_USER_AGENT        CONSTANT VARCHAR2(10) := 'User-Agent';
    HF_WWW_AUTHENTICATE  CONSTANT VARCHAR2(16) := 'WWW-Authenticate';
    HF_HOST              CONSTANT VARCHAR2(04) := 'Host';
    HF_ACCEPT            CONSTANT VARCHAR2(06) := 'Accept';
    HF_CONNECTION        CONSTANT VARCHAR2(10) := 'Connection';
    HF_TRANSFER_ENCODING CONSTANT VARCHAR2(17) := 'Transfer-Encoding';
    HF_TE                CONSTANT VARCHAR2(02) := 'TE';
    HV_CHUNKED           CONSTANT VARCHAR2(07) := 'chunked';
    HV_USER_AGENT        CONSTANT VARCHAR2(09) := 'ibm-calif';
    HV_CONTENT_TYPE      CONSTANT VARCHAR2(08) := 'text/xml';

    /* ERROR CODES
    */
    -- SUCCESS
    OK_REQUEST_SUCCEEDED           CONSTANT NUMBER := 200;
    OK_NEW_RESOURCE_CREATED        CONSTANT NUMBER := 201;
    OK_REQUEST_ACCE_PROC_NOT_COMPL CONSTANT NUMBER := 202;
    OK_NO_CONTENT_TO_RETURN        CONSTANT NUMBER := 204;
    HTTP_RETCODE_MAX_OK            CONSTANT NUMBER := 299;

    -- REDIRECTION
    REDIR_RESOURC_HAS_NEW_PERM_URL CONSTANT NUMBER := 301;
    REDIR_RESOURC_HAS_NEW_TEMP_URL CONSTANT NUMBER := 302;
    REDIR_DOC_NOT_BEEN_MODIFIED    CONSTANT NUMBER := 304;

    -- CLIENT ERROR
    CLT_ERR_BAD_REQUEST            CONSTANT NUMBER := 400;
    CLT_ERR_UNAUTHORIZED           CONSTANT NUMBER := 401;
    CLT_ERR_FORBIDDEN_UNSPEC_REAS  CONSTANT NUMBER := 403;
    CLT_ERR_NOT_FOUND              CONSTANT NUMBER := 404;

    -- SERVER ERROR
    SRV_ERR_INTERNAL_ERROR         CONSTANT NUMBER := 500;
    SRV_ERR_NOT_IMPLEMENTED        CONSTANT NUMBER := 501;
    SRV_ERR_BAD_GATEWAY            CONSTANT NUMBER := 502;
    SRV_ERR_RESOURCE_TEMP_UNAVAIL  CONSTANT NUMBER := 503;


    /* global variables
    */
    v_xml_in             XMLTYPE;
    v_xml_out            XMLTYPE;
    v_reply_error_code   VARCHAR2(16);
    v_reply_error_orig   VARCHAR2(16);
    v_reply_error_desc   VARCHAR2(255);
    v_location           VARCHAR2(32);

    calvin_session_id    CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE;

    /*
    ** Provide Calvin Session ID for Calvin requests during this database call.
    */
    PROCEDURE set_calvin_session_id(
        p_calvin_session_id CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE
    )
    IS
    BEGIN
        calvin_session_id:= p_calvin_session_id;
    END set_calvin_session_id;

    /*
    ** If this call is bound to a customer session, return the Calvin Session
    ** ID, otherwise return NULL.
    */
    FUNCTION get_calvin_session_id
    RETURN   CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE
    IS
    BEGIN
        RETURN calvin_session_id;
    END get_calvin_session_id;

    /*
    ** Reset calvin session id
    */
    PROCEDURE reset_calvin_session_id
    IS
    BEGIN
        calvin_session_id := NULL;
    END;

    /*
    ** This internal procedure handles an error message
    ** it creates a server log entry and a dashboard entry (if neccessary)
    ** and then raises an exception.
    */
    PROCEDURE log_and_raise_error(
        p_error_message     IN VARCHAR2,
        p_create_event      IN CHAR := 'N'
    )
    IS
        v_session_language CHAR(3);
    BEGIN
        IF p_create_event = 'Y'
        THEN
            dashboard.emit(p_error_message);
        END IF;

        error.log_message(
            p_location  =>  v_location,
            p_message   =>  p_error_message,
            p_severity  =>  error.severity_error
        );

        RAISE_APPLICATION_ERROR(
            error.application_error_no,
            p_error_message
        );
    END log_and_raise_error;

    /*
    ** This internal procedure handles a calvin error message
    */
    PROCEDURE error_handling
    IS
        v_calvin_error_mapping CALVIN_ERROR_MAPPING%ROWTYPE;
    BEGIN
        /*
        ** determine internal error code
        */
        BEGIN
            SELECT cem.*
              INTO v_calvin_error_mapping
              FROM CALVIN_ERROR_MAPPING cem,
                   ERROR_FORMAT ef
             WHERE cem.EXT_ERROR_CODE     = v_reply_error_orig
               AND cem.EXT_ERROR_SUB_CODE = v_reply_error_code
               AND cem.ERROR_NO           = ef.ERROR_NO;
        EXCEPTION
        WHEN OTHERS
        THEN
            NULL;
        END;

        IF v_calvin_error_mapping.ERROR_NO is NULL
        THEN
            BEGIN
                SELECT cem.*
                  INTO v_calvin_error_mapping
                  FROM CALVIN_ERROR_MAPPING cem,
                       ERROR_FORMAT ef
                 WHERE cem.EXT_ERROR_CODE     = v_reply_error_orig
                   AND cem.EXT_ERROR_SUB_CODE = 'DEFAULT'
                   AND cem.ERROR_NO           = ef.ERROR_NO;
            EXCEPTION
            WHEN OTHERS
            THEN
                NULL;
            END;

            IF v_calvin_error_mapping.ERROR_NO is NULL
            THEN
                BEGIN
                    SELECT cem.*
                      INTO v_calvin_error_mapping
                      FROM CALVIN_ERROR_MAPPING cem,
                           ERROR_FORMAT ef
                     WHERE cem.EXT_ERROR_CODE     = 'DEFAULT'
                       AND cem.EXT_ERROR_SUB_CODE = 'DEFAULT'
                       AND cem.ERROR_NO           = ef.ERROR_NO;
                EXCEPTION
                WHEN OTHERS
                THEN
                    v_calvin_error_mapping.ERROR_NO     := 10009;
                    v_calvin_error_mapping.CREATE_EVENT := 'Y';
                END;
            END IF;
        END IF;

        log_and_raise_error(
            p_error_message => error.format(
                                   v_calvin_error_mapping.ERROR_NO,
                                   v_reply_error_orig || ' ' || v_reply_error_code
                               ),
            p_create_event  => v_calvin_error_mapping.CREATE_EVENT
        );
    END error_handling;

    /*
    ** This internal procedure converts a string to a format
    ** that can be send via http
    */
    FUNCTION convert_to_http_char_set(
        p_str               IN VARCHAR2
    )
    RETURN VARCHAR2
    IS
    BEGIN
        RETURN CONVERT(NVL(TRIM(p_str), ''), 'US7ASCII');
    END convert_to_http_char_set;

    /*
    ** This internal procedure determines the needed URL
    */
    FUNCTION get_url(
        p_url VARCHAR2
    )
    RETURN VARCHAR2
    IS
        v_proto     VARCHAR2(255);
        v_server    VARCHAR2(255);
        v_port      VARCHAR2(255);
        v_path      VARCHAR2(255);
        v_remainder VARCHAR2(255);

        v_pos       NUMBER;
        v_del_count NUMBER := 0;
        v_i         NUMBER;
        b_has_port  BOOLEAN := FALSE;
    BEGIN
        IF p_url IS NULL
        THEN
            RAISE_APPLICATION_ERROR(
                error.application_error_no,
                'Malformed URL: No data given'
            );
        END IF;

        /* check for protocol first
        */
        IF LOWER(SUBSTR(p_url, 1, 4)) = HTTP_PROTO
        THEN
            /* in this case we need the colon
            */
            v_pos := INSTR(p_url, ':');
            IF (v_pos != 0)
            THEN
                /* Proto given
                */
                v_proto     := SUBSTR(p_url, 1, v_pos - 1);
                v_remainder := SUBSTR(p_url, v_pos + 1);

                /* check for double slashes
                */
                IF SUBSTR(v_remainder, 1, 2) != SLASH || SLASH
                THEN
                    RAISE_APPLICATION_ERROR(
                        error.application_error_no,
                        'Malformed URL: No // in front of IP Address');
                END IF;
            ELSE
                /* no colon -> 'http' is not regarded as part of the protocol
                */
                v_proto     := HTTP_PROTO;
                v_remainder := p_url;
            END IF;
        ELSE
            /* no http(s) at start of string
            */
            v_proto     := HTTP_PROTO;
            v_remainder := p_url;
        END IF;

        /*
        ** now we have a string of format [//]ip-address[:port][/PATHandRest]
        ** look for the next colon
        */
        v_pos := INSTR(v_remainder, ':');

        IF (v_pos != 0)
        THEN
            /* Port given
            */
            v_server    := SUBSTR(v_remainder, 1, v_pos - 1);
            v_remainder := SUBSTR(v_remainder, v_pos + 1);
            b_has_port  := TRUE;
        ELSE
            /* no protocol -> use default
            */
            v_port  := DEFAULT_HTTP_PORT;
        END IF;


        /* remove first two leading slashes (if existing)
        */
        IF SUBSTR(v_remainder, 1, 1) = SLASH
        THEN
            v_del_count := v_del_count + 1;
            IF SUBSTR(v_remainder, 2, 1) = SLASH
            THEN
                v_del_count := v_del_count + 1;
            END IF;
        END IF;

        v_remainder := SUBSTR(v_remainder, v_del_count);

        /* check for path (leading slash)
        */
        v_pos := INSTR(v_remainder, SLASH);

        IF (v_pos != 0)
        THEN
            /* Path given
            */
            IF (b_has_port)
            THEN
                v_port   := SUBSTR(v_remainder, 1, v_pos - 1);
            ELSE
                v_server := SUBSTR(v_remainder, 1, v_pos - 1);
            END IF;

            v_path := SUBSTR(v_remainder, v_pos);
        ELSE
            /* No path given
            */
            IF (b_has_port)
            THEN
                v_port   := v_remainder;
            ELSE
                v_server := v_remainder;
            END IF;
        END IF;

        /* delete leading colons
        */
        v_port := REGEXP_REPLACE(v_port, '^:*', '');

        /* use default if nothing given
        */
        IF v_port IS NULL OR LENGTH(v_port) = 0
        THEN
            v_port := DEFAULT_HTTP_PORT;
        END IF;

        IF v_path IS NULL OR LENGTH(v_path) = 0
        THEN
            v_path := SLASH;
        END IF;

        /* delete leading slashes
        */
        v_server := REGEXP_REPLACE(v_server, '^' || SLASH || '*', '');

        IF v_server IS NULL OR LENGTH(v_server) = 0
        THEN
            RAISE_APPLICATION_ERROR(
                error.application_error_no,
                'Malformed URL: NO IP-Address given');
        END IF;

        RETURN v_proto || '://' || v_server || ':' || v_port || v_path;

    EXCEPTION
    WHEN OTHERS THEN
         log_and_raise_error(
             p_error_message => SUBSTR(SQLERRM(), 1, 200)
         );
    END get_url;

    /*
    ** This internal procedure logs the passed message string into
    ** a specific calvin log file.
    */
    PROCEDURE log_to_file(
        p_log_str   VARCHAR2,
        p_log_level NUMBER,
        p_severity  usertype.LOG_SEVERITY := NULL
    )
    IS
        v_severity  usertype.LOG_SEVERITY;
        v_len       NUMBER;
        v_log_str   VARCHAR2(4000);
        v_pin_str   VARCHAR2(4000);
        v_tan_str   VARCHAR2(4000);
        v_dummy     BINARY_INTEGER;
    BEGIN
        /*
        ** Security:
        ** Don't show PIN and TAN values in log. Replace values by same number of
        ** asterisk characters.
        */
        v_pin_str := REGEXP_SUBSTR(p_log_str, '<PIN>.*</PIN>', 1, 1, 'i');
        IF v_pin_str IS NOT NULL
        THEN
            v_pin_str :=    '<PIN>'
                         || RPAD('*',
                                LENGTH(
                                    LTRIM(RTRIM(REGEXP_SUBSTR(v_pin_str, '>.*<'), '<'), '>')
                                ), '*'
                            )
                         || '</PIN>';
        END IF;

        v_tan_str := REGEXP_SUBSTR(p_log_str, '<TAN>.*</TAN>', 1, 1, 'i');
        IF v_tan_str IS NOT NULL
        THEN
            v_tan_str :=    '<TAN>'
                         || RPAD('*',
                                LENGTH(
                                    LTRIM(RTRIM(REGEXP_SUBSTR(v_tan_str, '>.*<'), '<'), '>')
                                ), '*'
                            )
                         || '</TAN>';
        END IF;

        v_log_str := SUBSTR(REGEXP_REPLACE(p_log_str, '<PIN>[^<]*</PIN>', v_pin_str, 1, 1, 'i'), 1, 4000);
        v_log_str := SUBSTR(REGEXP_REPLACE(v_log_str, '<TAN>[^<]*</TAN>', v_tan_str, 1, 1, 'i'), 1, 4000);

        /* strip trailing EOL
        */
        v_len := LENGTH(v_log_str);
        WHILE v_len > 0 AND SUBSTR(v_log_str, v_len, 1) = CHR(10)
        LOOP
            v_len := v_len - 1;
        END LOOP;

        v_severity := NVL(p_severity, error.severity_info);

        IF (v_severity >= error.severity_info AND p_log_level >= 2)
        OR (v_severity <  error.severity_info AND p_log_level >= 1)
        THEN
            error.log_message(
                p_location  => v_location,
                p_message   => SUBSTR(v_log_str, 1, v_len),
                p_severity  => v_severity,
                p_file      => c_log_file
            );
        END IF;
    END;

    /*
    ** This internal procedure logs the passed XMLTYPE into
    ** a specific calvin log file.
    */
    PROCEDURE log_to_file(
        p_header    VARCHAR2,
        p_xml       XMLTYPE,
        p_log_level NUMBER,
        p_severity  usertype.LOG_SEVERITY := NULL
    )
    IS
    BEGIN
        log_to_file(
            p_log_str   => SUBSTR(p_header || p_xml.getCLOBVal(), 1, 4000),
            p_log_level => p_log_level,
            p_severity  => p_severity
        );
    END log_to_file;

    /*
    ** This internal procedure logs the passed URL into
    ** a specific calvin log file.
    */
    PROCEDURE log_url(
        p_url                  VARCHAR2,
        p_request_service_name VARCHAR2,
        p_request_feid         VARCHAR2,
        p_request_language     VARCHAR2,
        p_request_session_id   VARCHAR2,
        p_log_level            NUMBER
    )
    IS
    BEGIN
        log_to_file(
            p_log_str =>
                'CALVIN query [ server=''' || TRIM(p_url) ||
                ''', service=''' || TRIM(p_request_service_name) ||
                ''', frontendID=''' || TRIM(p_request_feid) ||
                ''', language=''' || TRIM(p_request_language) ||
                ''', sessionID=''' || TRIM(p_request_session_id) || ''']',
            p_log_level => p_log_level
        );
    END log_url;


    /*
    ** This internal function builds the HTTP interface
    */
    PROCEDURE http_request(
        p_url           VARCHAR2,
        p_xml_in    IN  XMLTYPE,
        p_xml_out   OUT XMLTYPE,
        p_log_level     NUMBER
    )
    IS
        v_http_req      UTL_HTTP.REQ;
        v_http_resp     UTL_HTTP.RESP;
        v_xml_str       VARCHAR2(32767);
        v_xml_clob      CLOB;
        v_wallet_pth    VARCHAR2(60);
        v_wallet_pwd    VARCHAR2(60);
    BEGIN
        log_to_file(
            p_header    => c_text_request || c_xml_header,
            p_xml       => p_xml_in,
            p_log_level => p_log_level
        );

        v_wallet_pth:= parameter_tool.get_parameter_value('WALLET');
        IF v_wallet_pth IS NOT NULL
        THEN
            v_wallet_pwd:= parameter_tool.get_parameter_value('WALLET_PWD');
            UTL_HTTP.SET_WALLET(v_wallet_pth, v_wallet_pwd);
        END IF;

        v_http_req := UTL_HTTP.BEGIN_REQUEST(p_url, 'GET', 'HTTP/1.1');

        UTL_HTTP.SET_HEADER(v_http_req, HF_USER_AGENT, HV_USER_AGENT);
        UTL_HTTP.SET_HEADER(v_http_req, HF_TE, HV_CHUNKED);
        UTL_HTTP.SET_HEADER(v_http_req, HF_CONTENT_LENGTH,
            LENGTH(c_xml_header) + LENGTH(p_xml_in.getCLOBVal()));

        UTL_HTTP.WRITE_TEXT(v_http_req, c_xml_header || p_xml_in.getCLOBVal());

        v_http_resp := UTL_HTTP.GET_RESPONSE(v_http_req);

        BEGIN
            LOOP
                UTL_HTTP.READ_TEXT(v_http_resp, v_xml_str, 32767);
                v_xml_clob := v_xml_clob || TO_CHAR(v_xml_str);
            END LOOP;
        EXCEPTION WHEN UTL_HTTP.END_OF_BODY
        THEN
            NULL;
        END;

        UTL_HTTP.END_RESPONSE(v_http_resp);

        p_xml_out := XMLTYPE(v_xml_clob);
    EXCEPTION
    WHEN OTHERS THEN
         log_and_raise_error(
             p_error_message => SUBSTR(SQLERRM(), 1, 200)
         );
    END http_request;

    /*
    ** This internal procedure encapsulates all actual communication
    ** with Calvin.
    */
    PROCEDURE
    calvin_query(
        p_request_service_name  IN  VARCHAR2,
        p_request_version_no    IN  VARCHAR2 := NULL,
        p_request_session_id    IN  VARCHAR2,
        p_calv_onfs_st          IN  VARCHAR2,
        p_update_session_id     IN  BOOLEAN  := TRUE,
        p_xml_in                IN  XMLTYPE,
        p_xml_out               OUT XMLTYPE
    )
    AS
        v_reply_session_id          VARCHAR2(64);

        v_reply_code                PLS_INTEGER;
        v_request_log_level         PLS_INTEGER;
        v_primary_server_address    CHAR(60);
        v_backup_server_address     CHAR(60);
        v_request_feid              VARCHAR2(64);
        v_request_language          VARCHAR2(2);
        v_request_session_id        VARCHAR2(64);
        v_url                       VARCHAR2(2000);
        v_xml_in                    XMLTYPE;
    BEGIN
        /*
        ** retrieve needed communication information
        */
        v_request_log_level :=
            TO_NUMBER(parameter_tool.get_parameter_value('CALV_LOG_LVL'));

        CASE p_calv_onfs_st
            WHEN '0'
            THEN
                v_primary_server_address :=
                    parameter_tool.get_parameter_value('CALV_ADDR');

                v_backup_server_address :=
                    parameter_tool.get_parameter_value('CALV_BACKUP');

            WHEN '1'
            THEN
                v_primary_server_address :=
                    parameter_tool.get_parameter_value('CALV_ONFS_1');

                v_backup_server_address :=
                    parameter_tool.get_parameter_value('CALV_ONFS_1');

            ELSE
                v_primary_server_address :=
                    parameter_tool.get_parameter_value('CALV_ONFS_2');

                v_backup_server_address :=
                    parameter_tool.get_parameter_value('CALV_ONFS_2');
        END CASE;

        v_request_feid :=
            parameter_tool.get_parameter_value('CALV_FEID');

        v_request_language       := 'DE';
        v_request_session_id     := CONVERT(p_request_session_id,'US7ASCII');

        /* build complete XML request
        */
        SELECT
            XMLELEMENT("request",
                XMLATTRIBUTES(convert_to_http_char_set(p_request_service_name)
                                  AS "servicename",
                              convert_to_http_char_set(p_request_session_id)
                                  AS "sessionid",
                              convert_to_http_char_set(v_request_feid)
                                  AS "feid",
                              convert_to_http_char_set(v_request_language)
                                  AS "language",
                              convert_to_http_char_set(p_request_version_no)
                                  AS "version"
                             ),
            p_xml_in
        )
        INTO v_xml_in
        FROM DUAL;

        /* try primary server
        */
        BEGIN
            v_url := get_url(convert_to_http_char_set(v_primary_server_address)
                     );
            log_url(
                p_url                  => v_url,
                p_request_service_name => p_request_service_name,
                p_request_feid         => v_request_feid,
                p_request_language     => v_request_language,
                p_request_session_id   => p_request_session_id,
                p_log_level            => v_request_log_level
            );

            http_request(
                p_url     => v_url,
                p_xml_in  => v_xml_in,
                p_xml_out => p_xml_out,
                p_log_level => v_request_log_level
            );
        EXCEPTION
        WHEN OTHERS THEN
            /* try backup server */
            IF (v_backup_server_address IS NOT NULL                 AND
                v_backup_server_address != ' '                      AND
                v_backup_server_address != v_primary_server_address    )
            THEN
                v_url := get_url(
                             convert_to_http_char_set(v_backup_server_address)
                         );
                log_url(
                    p_url                  => v_url,
                    p_request_service_name => p_request_service_name,
                    p_request_feid         => v_request_feid,
                    p_request_language     => v_request_language,
                    p_request_session_id   => p_request_session_id,
                    p_log_level            => v_request_log_level
                );

                http_request(
                    p_url     => v_url,
                    p_xml_in  => v_xml_in,
                    p_xml_out => p_xml_out,
                    p_log_level => v_request_log_level
                );
            ELSE
                /* no valid backup server given; rethrow exception */
                RAISE;
            END IF;
        END;

        /* we have received an answer; try to extract error codes
        */
        SELECT
            TRIM(EXTRACTVALUE(p_xml_out, '/reply/@' || ATTR_ERROR_CODE)),
            TRIM(EXTRACTVALUE(p_xml_out, '/reply/@' || ATTR_ERROR_ORIG)),
            TRIM(EXTRACTVALUE(p_xml_out, '/reply/@' || ATTR_SESSION_ID)),
            SUBSTR(TRIM(EXTRACTVALUE(p_xml_out,
                                     '/reply/@' || ATTR_ERROR_DESC)
                       ),
                   1,
                   255)
        INTO
            v_reply_error_code,
            v_reply_error_orig,
            v_reply_session_id,
            v_reply_error_desc
        FROM
            DUAL;

        IF v_reply_error_code = '0'
        THEN
            /* log info
            */
            log_to_file(
                p_header    => c_text_response,
                p_xml       => p_xml_out,
                p_log_level => v_request_log_level
            );
        ELSE
            /* log error
            */
            log_to_file(
                p_log_str   => c_text_calvin_error || c_text_description ||
                               v_reply_error_desc,
                p_log_level => v_request_log_level,
                p_severity  => error.severity_error
            );

            log_to_file(
                p_header    => c_text_calvin_error || c_text_request ||
                               c_xml_header,
                p_xml       => v_xml_in,
                p_log_level => v_request_log_level,
                p_severity  => error.severity_error
            );

            IF p_xml_out IS NOT NULL
            THEN
                log_to_file(
                    p_header    => c_text_calvin_error || c_text_response,
                    p_xml       => p_xml_out,
                    p_log_level => v_request_log_level,
                    p_severity  => error.severity_error
                );
            END IF;
        END IF;

        /*
        ** log return code as info, even in case of no error
        */
        log_to_file(
            p_log_str   => 'CALVIN query returns with error code ' ||
                           v_reply_error_code,
            p_log_level => v_request_log_level
        );

        IF  (   (v_reply_error_code = '0')
            AND (   (v_request_session_id IS NULL)
                OR  (v_reply_session_id != v_request_session_id)
                )
            AND p_update_session_id
            )
        THEN
            /* keep Calvin session information up to date
            */
            parameter_tool.set_parameter_value(
                p_name  => 'CALV_SESS_ID',
                p_value => v_reply_session_id
            );
        END IF;
    END calvin_query;

    /*
    ** This internal procedure executes all requests to Calvin.
    ** It encapsulates Calvin session management.
    */
    PROCEDURE
    calvin_request(
        p_request_service_name  IN  VARCHAR2,
        p_request_version_no    IN  VARCHAR2 := NULL,
        p_calv_onfs_st          IN  VARCHAR2 := '0',
        p_xml_in                IN  XMLTYPE,
        p_xml_out               OUT XMLTYPE
    )
    AS
        v_loop_cnt                      SMALLINT;
        v_request_session_id            VARCHAR2(64);
        v_request_login_service_name    VARCHAR2(80);
        v_request_userid                VARCHAR2(64);
        v_request_pin                   VARCHAR2(64);
        v_session_ts                    VARCHAR2(14);
        v_session_tm                    NUMBER;
        v_session_expired               BOOLEAN;
        v_xml_login                     XMLTYPE;
    BEGIN
        v_loop_cnt  :=  1;

        LOOP
            /*
            ** Prefer personalized Session ID over common, technical SessionID.
            */
            v_request_session_id := calvin.get_calvin_session_id;
            IF v_request_session_id IS NULL
            THEN
                v_request_session_id := parameter_tool.get_parameter_value('CALV_SESS_ID');
            END IF;

            v_session_ts := SUBSTR(parameter_tool.get_parameter_value('CALV_SESS_TS'),1,14);

            IF (v_session_ts = '0')
            THEN
                v_session_ts := '20000101010000';
            END IF;

            v_session_tm := TO_NUMBER(parameter_tool.get_parameter_value('CALV_SESS_TM'));

            /*
            ** determine whether session is expired
            */
            IF SYSDATE >= TO_DATE(v_session_ts,'YYYYMMDDHH24MISS') +
                          (v_session_tm / (60 * 24))
            THEN
                v_session_expired := TRUE;
            ELSE
                v_session_expired := FALSE;
            END IF;

            /*
            ** calvin request - only if session refresh is not needed
            */
            IF (rtrim(v_request_session_id,' ') != '0' AND
                v_session_expired = FALSE                 )
            THEN
                calvin_query(
                    p_request_service_name  =>  p_request_service_name,
                    p_request_version_no    =>  p_request_version_no,
                    p_request_session_id    =>  v_request_session_id,
                    p_calv_onfs_st          =>  p_calv_onfs_st,
                    p_xml_in                =>  p_xml_in,
                    p_xml_out               =>  p_xml_out
                );

                IF (v_reply_error_code = '0')
                THEN
                    EXIT;
                END IF;
            END IF;

            /*
            ** calvin session refresh
            */
            IF  /*
                ** PARM.CALV_SESS_ID has been updated to 0 by trader
                */
                (rtrim(v_request_session_id,' ') = '0')
                OR
                /*
                ** session has been expired
                */
                (v_session_expired = TRUE)
                OR
                /*
                ** Tan-Validation failed because of invalid session
                */
                (   (v_reply_error_orig =   'msecs' )
                AND (v_loop_cnt         =   1       )
                )
            THEN
                v_request_login_service_name :=
                    parameter_tool.get_parameter_value('CALV_LOGIN');

                v_request_userid :=
                    parameter_tool.get_parameter_value('CALV_USER_ID');

                v_request_pin :=
                    parameter_tool.get_parameter_value('CALV_PIN');

                SELECT
                    XMLCONCAT(
                        XMLELEMENT("authtype", 'login'),
                        XMLELEMENT("userid",
                                   convert_to_http_char_set(v_request_userid)),
                        XMLELEMENT("pin",
                                   convert_to_http_char_set(v_request_pin))
                    )
                INTO v_xml_login
                FROM DUAL;

                calvin_query(
                    p_request_service_name  =>  v_request_login_service_name,
                    p_request_version_no    =>  p_request_version_no,
                    p_request_session_id    =>  NULL,
                    p_calv_onfs_st          =>  p_calv_onfs_st,
                    p_xml_in                =>  v_xml_login,
                    p_xml_out               =>  p_xml_out
                );

                IF (v_reply_error_code != '0')
                THEN
                    EXIT;
                ELSE
                    /*
                    ** Calvin session refesh was OK
                    */
                    v_session_expired := FALSE;

                    /*
                    ** update Calvin session refresh timestamp
                    */
                    parameter_tool.set_parameter_value(
                        p_name  => 'CALV_SESS_TS',
                        p_value => TO_CHAR(SYSDATE,'YYYYMMDDHH24MISS')
                    );
                END IF;

                v_loop_cnt  :=  v_loop_cnt + 1;
            ELSE
                EXIT;
            END IF;
        END LOOP;
    END calvin_request;

    /*
    ** This external procedure executes a TAN validation
    ** via the Calvin interface.
    */
    PROCEDURE tan_validate(
        p_cash_account_no   IN  CASH_ACCOUNTS.CASH_ACCOUNT_NO%TYPE,
        p_authorization_no  IN  CHAR,
        p_auth_method       IN  VARCHAR2 := NULL,
        p_tan               IN  VARCHAR2,
        p_tan_valid         OUT BOOLEAN
    )
    AS
        v_cash_account_no   VARCHAR2(17);
    BEGIN
        v_location        := 'calvin.tan_validate';
        v_cash_account_no := p_cash_account_no;  -- VNDL is already splitted
        p_tan_valid       := NULL;

        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_tan_valid := TRUE;
            RETURN;
        END IF;

        SELECT
            XMLCONCAT(
                XMLELEMENT("ACCOUNTNO",
                           convert_to_http_char_set(v_cash_account_no)),
                XMLELEMENT("AUTH_METHOD",
                           convert_to_http_char_set(p_auth_method)),
                XMLELEMENT("TAN",
                           convert_to_http_char_set(COALESCE(p_tan, '0'))),
                XMLELEMENT("ENTITLED",
                           convert_to_http_char_set(p_authorization_no))
            )
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWTanValidate',
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        /* return fields 'TANS_FREE' and 'DATASOURCE' are not used,
           so there is no need to evaluate the returned XML */

        IF (v_reply_error_code = '0')
        THEN
            p_tan_valid :=  TRUE;
        ELSE
            p_tan_valid :=  FALSE;
            error_handling;
        END IF;
    END tan_validate;

    /*
    ** This external procedure executes a underlying stock query
    ** via the CALVIN interface.
    */
    PROCEDURE
    underlying_stock_query(
        p_account_no    IN  ACCOUNTS.ACCOUNT_NO%TYPE,
        p_wkn           IN  EQTS.WKN%TYPE,
        p_available     OUT NUMBER,
        p_locked        OUT NUMBER
    )
    AS
        v_lock_flag     VARCHAR2(2);
        v_account_no    VARCHAR2(17);
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_available := 0;
            p_locked    := 0;
            RETURN;
        END IF;

        v_location   := 'calvin.underlying_stock_query';
        v_account_no := customer_tool.split_account_no(p_account_no, 0);

        v_lock_flag :=
            TRIM(parameter_tool.get_parameter_value('CALV_LOCK'));

        SELECT
            XMLCONCAT(
                XMLELEMENT("DEPOTNO",
                           convert_to_http_char_set(v_account_no)),
                XMLELEMENT("SECURITY_WKN",
                           convert_to_http_char_set(SUBSTR(p_wkn,7,6))),
                XMLELEMENT("LOCK_MARK",
                           convert_to_http_char_set(v_lock_flag))
            )
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWEurexPositionInq',
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            SELECT
                TRUNC(TO_NUMBER(TRIM(EXTRACTVALUE(v_xml_out,
                                                  '/reply/POSITION_FREE')))),
                TRUNC(TO_NUMBER(TRIM(EXTRACTVALUE(v_xml_out,
                                                  '/reply/POSITION_LOCKED'))))
            INTO
                p_available,
                p_locked
            FROM
                DUAL;
        ELSE
            error_handling;
        END IF;
    END underlying_stock_query;

    /*
    ** This external procedure executes a underlying stock lock
    ** via the CALVIN interface.
    */
    PROCEDURE
    underlying_stock_lock(
        p_action_flag   IN  CHAR,
        p_account_no    IN  ACCOUNTS.ACCOUNT_NO%TYPE,
        p_wkn           IN  EQTS.WKN%TYPE,
        p_quantity      IN  NUMBER,
        p_order_no      IN  ORDR.ORDER_NO%TYPE,
        p_lock_until    IN  DATE,
        p_success_flag  OUT BOOLEAN
    )
    AS
        v_lock_flag         VARCHAR2(2);
        v_action_flag       CHAR;
        v_lock_until        CHAR(10);
        v_order_no          VARCHAR2(8);
        v_account_no        VARCHAR2(17);
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_success_flag := TRUE;
            RETURN;
        END IF;

        v_location   := 'calvin.underlying_stock_lock';
        v_account_no := customer_tool.split_account_no(p_account_no, 0);

        v_lock_flag :=
            TRIM(parameter_tool.get_parameter_value('CALV_LOCK'));

        /*
        ** pad incomming parameters with leading zeros
        */
        v_order_no   :=  LPAD (p_order_no, 8, '0') ;
        v_lock_until :=  TO_CHAR(p_lock_until, 'YYYY-MM-DD');

        /*
        ** check parameter consistency
        */
        IF p_action_flag NOT IN ('F', 'S')
        THEN
            log_and_raise_error(
                error.format(1202, p_action_flag, 'p_action_flag')
            );
        ELSE
            IF p_action_flag = 'F'
            THEN
                v_action_flag := '0';
            ELSE
                v_action_flag := '1';
            END IF;
        END IF;

        SELECT
            XMLCONCAT(
                XMLELEMENT("DEPOTNO",
                           convert_to_http_char_set(v_account_no)),
                XMLELEMENT("MODE",
                           convert_to_http_char_set(v_action_flag)),
                XMLELEMENT("SECURITY_WKN",
                           convert_to_http_char_set(SUBSTR(p_wkn,7,6))),
                XMLELEMENT("LOCK_MARK",
                           convert_to_http_char_set(v_lock_flag)),
                XMLELEMENT("SECURITY_NOMINAL_AMOUNT",
                           convert_to_http_char_set(TO_CHAR(p_quantity))),
                XMLELEMENT("ORDERNO",
                           convert_to_http_char_set(v_order_no)),
                XMLELEMENT("BLOCKED_UNTIL",
                           convert_to_http_char_set(v_lock_until))
            )
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWEurexPositionLock',
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            p_success_flag  :=  TRUE;
        ELSE
            p_success_flag  :=  FALSE;
        END IF;
    END underlying_stock_lock;

    /*
    ** This external procedure executes a account balance query
    ** via the CALVIN interface.
    */
    PROCEDURE
    account_balance_query(
        p_account_no            IN  ACCOUNTS.ACCOUNT_NO%TYPE,
        p_curr                  OUT CASH_ACCOUNTS.CACC_CURR%TYPE,
        p_mgn_acct_credit       OUT NUMBER,
        p_mgn_acct_int_credit   OUT NUMBER,
        p_stock_value           OUT NUMBER,
        p_stock_value_rated     OUT NUMBER,
        p_cash_balance          OUT NUMBER,
        p_overall_balance       OUT NUMBER,
        p_market_val_acct_assoc OUT NUMBER,
        p_further_margin_acct   OUT CHAR
    )
    AS
        v_curr                      VARCHAR2(4);
        v_mgn_acct_credit           VARCHAR2(17);
        v_mgn_acct_int_credit       VARCHAR2(17);
        v_stock_value               VARCHAR2(17);
        v_stock_value_rated         VARCHAR2(17);
        v_cash_balance              VARCHAR2(17);
        v_overall_balance           VARCHAR2(17);
        v_market_value              VARCHAR2(19);
        v_additional_dispo_compound VARCHAR2(5);
        v_account_no                VARCHAR2(17);

        FUNCTION string_to_number(p_string VARCHAR2)
        RETURN   NUMBER
        IS
            v_string VARCHAR2(32);
            v_fmt    VARCHAR2(32);
        BEGIN
            /*
            ** Conversion must happen independent of caller's NLS settings.
            */
            v_string := REPLACE(p_string, ',', '.');
            v_fmt    := LTRIM(v_string, '-');
            RETURN TO_NUMBER(v_string,
                             -- Create suitable number format on the fly.
                             TRANSLATE(v_fmt, '1234567890', '9999999999'),
                             -- Decimal character is "."
                             'NLS_NUMERIC_CHARACTERS = ''.,''');
        EXCEPTION
        WHEN OTHERS
        THEN
            error.log_message(v_location,
                              'Failed to convert string [' || p_string
                              || '] to number: ' || SQLCODE || ': ' || SQLERRM,
                              error.severity_error);
            RAISE;
        END string_to_number;
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_curr                  := ' ';
            p_mgn_acct_credit       := 0;
            p_mgn_acct_int_credit   := 0;
            p_stock_value           := 0;
            p_stock_value_rated     := 0;
            p_cash_balance          := 0;
            p_overall_balance       := 0;
            p_market_val_acct_assoc := 0;
            p_further_margin_acct   := ' ';

            RETURN;
        END IF;

        v_location   := 'calvin.account_balance_query';
        v_account_no := customer_tool.split_account_no(p_account_no, 0);

        SELECT
            XMLELEMENT("DEPOTNO", convert_to_http_char_set(v_account_no))
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWEurexAccountInq',
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            SELECT
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/CURRENCY')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/MARGIN_ACCOUNT_DISPO')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/MARGIN_ACCOUNT_LIMIT')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/CASH_ACCOUNT_DISPO')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/DEPOT_BALANCE')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/DEPOT_BALANCE_LENDABLE')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/SALDO')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/MARKET_VALUE')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/ADDITIONAL_DISPO_COMPOUND'))
            INTO
                v_curr,
                v_mgn_acct_credit,
                v_mgn_acct_int_credit,
                v_cash_balance,
                v_stock_value,
                v_stock_value_rated,
                v_overall_balance,
                v_market_value,
                v_additional_dispo_compound
            FROM
                DUAL;

            p_curr                  := v_curr;
            p_mgn_acct_credit       := string_to_number(v_mgn_acct_credit);
            p_mgn_acct_int_credit   := string_to_number(v_mgn_acct_int_credit);
            p_stock_value           := string_to_number(v_stock_value);
            p_stock_value_rated     := string_to_number(v_stock_value_rated);
            p_cash_balance          := string_to_number(v_cash_balance);
            p_overall_balance       := string_to_number(v_overall_balance);
            p_market_val_acct_assoc := string_to_number(v_market_value);

            IF UPPER(TRIM(v_additional_dispo_compound)) = 'TRUE'
            THEN
                p_further_margin_acct := 'Y';
            ELSE
                p_further_margin_acct := 'N';
            END IF;
        ELSE
            error_handling;
        END IF;

    END account_balance_query;

    /*
    ** This external procedure executes a cash transfer
    ** via the CALVIN interface.
    */
    PROCEDURE
    account_transfer(
        p_account_owner     IN  CUSTOMERS.CUSTOMER_NO%TYPE,
        p_curr              IN  CASH_ACCOUNTS.CACC_CURR%TYPE,
        p_account_minus     IN  CHAR,               --Marginaccount
        p_blz               IN  VARCHAR2,
        p_account_plus      IN  CASH_ACCOUNTS.CASH_ACCOUNT_NO%TYPE,
        p_amount            IN  NUMBER,
        p_authorization_no  IN  CHAR,
        p_tan               IN  VARCHAR2
    )
    AS
        v_account_minus         VARCHAR2(17);
        v_account_plus          VARCHAR2(17);
        v_accounts              ACCOUNTS%ROWTYPE;
        v_customers             CUSTOMERS%ROWTYPE;
        v_receiver              VARCHAR2(27);
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            RETURN;
        END IF;

        v_location := 'calvin.account_transfer';
        v_account_minus := customer_tool.split_account_no(p_account_minus, 0);
        v_account_plus  := customer_tool.split_account_no(p_account_plus, 0);

        /* determine name of account owner
        */
        sp_customer_select(
            p_customer_no => p_account_owner,
            p_customer    => v_customers
        );

        v_receiver := substr(RTRIM(v_customers.NAME_2) ||
                             ' ' ||
                             RTRIM(v_customers.NAME_1), 1, 27);
        SELECT
            XMLCONCAT(
                XMLELEMENT("ENTITLED",
                           convert_to_http_char_set(p_authorization_no)),
                XMLELEMENT("VALIDATE_ONLY",
                           convert_to_http_char_set('0')),
                XMLELEMENT("AUTHORIZATION_TYPE",
                           convert_to_http_char_set('T')),
                XMLELEMENT("TAN",
                           convert_to_http_char_set(p_tan)),
                XMLELEMENT("ACCOUNTNO",
                           convert_to_http_char_set(v_account_minus)),
                XMLELEMENT("ACCOUNTNO_RECEIVER",
                           convert_to_http_char_set(v_account_plus)),
                XMLELEMENT("AMOUNT",
                           convert_to_http_char_set(
                               REPLACE(TO_CHAR(p_amount),',', '.'))),
                XMLELEMENT("BANK_CODE",
                           convert_to_http_char_set(p_blz)),
                XMLELEMENT("CURRENCY",
                           convert_to_http_char_set(p_curr)),
                XMLELEMENT("PURPOSE_1",
                           convert_to_http_char_set(
                               'Umbuchung vom Marginkonto')),
                XMLELEMENT("PURPOSE_2",
                           convert_to_http_char_set(' ')),
                XMLELEMENT("RECEIVER",
                           convert_to_http_char_set(
                               common_tool.convert_string(v_receiver)))
            )
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWEurexCashTransfer',
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        /*
        ** return fields are not used,
        ** so there is no need to evaluate the returned XML
        */

        IF (v_reply_error_code != '0')
        THEN
            error_handling;
        END IF;
    END account_transfer;

    /*
    ** This procedure replaces account_transfer and initiates a SEPA
    ** cash transfer on the new SOAP based Calvin interface.
    */
    PROCEDURE
    sepa_cash_transfer(
        p_crm_customerno    IN VARCHAR2,
        p_account_minus     IN VARCHAR2, -- Margin Account
        p_iban              IN VARCHAR2, -- Beneficiary Account
        p_amount            IN NUMBER,
        p_authorization_no  IN VARCHAR2,
        p_purpose           IN VARCHAR2,
        p_tan               IN VARCHAR2,
        p_auth_method       IN VARCHAR2 DEFAULT NULL
    )
    IS
        v_account_minus VARCHAR2(17);
        v_error_msg     VARCHAR2(1000);
        v_xml_doc       XMLTYPE;
    BEGIN
        -- Check if we are running in emergency mode.
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN RETURN;
        END IF;

--      v_account_minus := customer_tool.split_account_no(p_account_minus, 0);
        v_account_minus := rtrim (p_account_minus);
        IF length (v_account_minus) > 9
        THEN
            v_account_minus := substr (v_account_minus, -9);
        END IF;

        SELECT XMLElement("OROMSepaCashTransfer",
                   XMLConcat(
                       XMLElement("crm_customerno",     p_crm_customerno),
                       XMLElement("accountno",          v_account_minus),
                       XMLElement("amount",             TO_NUMBER(p_amount)),
                       XMLElement("authorization_type", p_authorization_no),
                       XMLElement("iban_opponent",      p_iban),
                       XMLElement("purpose_1",          p_purpose),
                       XMLElement("tan",                p_tan),
                       XMLElement("auth_method",        p_auth_method),
                       XMLElement("validate_only",      'false')
                   )
               )
        INTO   v_xml_doc
        FROM   DUAL;

        v_error_msg := calvin_soap.request(v_xml_doc);

        IF v_error_msg IS NOT NULL
        THEN
            IF v_error_msg = 'timeout'
            THEN RAISE_APPLICATION_ERROR(error.application_error_no, error.format(2321));
            ELSE RAISE_APPLICATION_ERROR(error.application_error_no, v_error_msg);
            END IF;
        END IF;
    END;

    /*
    ** This procedure initiates a check if the customer has read-only permissions.
    ** In this case no validation (hard lock) is to take place during the order processing by the user.
    ** An order request will not be possible any longer. No changes / deletions are allowed.
    */
    PROCEDURE
    read_authentication_reply(
        p_crm_customerno    IN VARCHAR2,
        p_frontend_id       IN VARCHAR2,
        p_userid            IN VARCHAR2,
        p_entitled          IN VARCHAR2,
        p_realm             IN VARCHAR2,
        p_ip_adr            IN VARCHAR2,
        p_xml_res_doc      OUT XMLTYPE
    )
    IS
        v_error_msg     VARCHAR2(1000);
        v_xml_doc       XMLTYPE;
    BEGIN
        -- Check if we are running in emergency mode.
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN RETURN;
        END IF;

        SELECT XMLElement("OROMReadAuthReply",
                   XMLConcat(
                       XMLElement("crm_customerno",     convert_to_http_char_set(p_crm_customerno)),
                       XMLElement("frontend_id",        convert_to_http_char_set(p_frontend_id)),
                       XMLElement("userid",             convert_to_http_char_set(p_userid)),
                       XMLElement("entitled",           convert_to_http_char_set(p_entitled)),
                       XMLElement("realm",              convert_to_http_char_set(p_realm)),
                       XMLElement("ip_adr",             convert_to_http_char_set(p_ip_adr))
                   )
               )
        INTO   v_xml_doc
        FROM   DUAL;

        v_error_msg := calvin_soap.request(v_xml_doc, p_xml_res_doc);

        IF v_error_msg IS NOT NULL
        THEN
            IF v_error_msg = 'timeout'
            THEN RAISE_APPLICATION_ERROR(error.application_error_no, error.format(2321));
            ELSE RAISE_APPLICATION_ERROR(error.application_error_no, v_error_msg);
            END IF;
        END IF;
    END;

    /*
    ** Convert session token into new session id associated with Future.Trader
    ** frontend id. In fact this calls the same service as authenticate(2) but
    ** does not return unneeded reply values.
    */
    PROCEDURE authenticate(
        p_session_token       IN            VARCHAR2,
        p_request_session_id     OUT NOCOPY CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE,
        p_crm_customer_no        OUT NOCOPY VARCHAR2
    )
    AS
    BEGIN
        v_location := 'calvin.authenticate';

        SELECT XMLELEMENT(
                   "SESSION_TOKEN",
                   convert_to_http_char_set(p_session_token)
               )
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWConvertSessionToken',
            p_request_version_no    => '3',
            p_calv_onfs_st          => parameter_tool.get_parameter_value('CALV_ONFS_ST'),
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            /* get identification of customer
            */
            SELECT TRIM(EXTRACTVALUE(v_xml_out, '/reply/NEW_SESSION_ID')),
                   TRIM(EXTRACTVALUE(v_xml_out, '/reply/CRM_CUSTOMERNO'))
            INTO   p_request_session_id,
                   p_crm_customer_no
            FROM   DUAL;
        ELSE
            error_handling;
        END IF;
    END;

    /*
    ** This external procedure executes an authentication
    ** via the Calvin interface.
    */
    PROCEDURE authenticate(
        p_session_token       IN            CHAR,
        p_customer_no            OUT NOCOPY CUSTOMER_SESSION.CUSTOMER_NO%TYPE,
        p_session_tan_active     OUT NOCOPY CUSTOMER_SESSION.SESSION_TAN_ACTIVE%TYPE, -- Y/N
        p_mtan_active            OUT NOCOPY CUSTOMER_SESSION.MTAN_ACTIVE%TYPE,        -- Y/N
        p_request_session_id     OUT NOCOPY CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE,
        p_active_auth_methods    OUT NOCOPY dbms_sql.varchar2_table
    )
    AS
        v_request_session_id     VARCHAR2(64);
        v_contact_objid          VARCHAR2(20);
        v_session_tan_status     CHAR(1);
        v_auth_status            CHAR(1);
    BEGIN
        v_location := 'calvin.authenticate';

        SELECT
            XMLELEMENT("SESSION_TOKEN",
                       convert_to_http_char_set(p_session_token))
        INTO v_xml_in
        FROM DUAL;

        calvin_request(
            p_request_service_name  => 'MWConvertSessionToken',
            p_request_version_no    => '3',
            p_calv_onfs_st          => parameter_tool.get_parameter_value('CALV_ONFS_ST'),
            p_xml_in                => v_xml_in,
            p_xml_out               => v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            /* get identification of customer
            */
            SELECT
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/CRM_CUSTOMERNO')),
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/NEW_SESSION_ID'))
            INTO
                v_contact_objid,
                v_request_session_id
            FROM
                DUAL;

            SELECT AUTH_TYPE
            BULK COLLECT INTO p_active_auth_methods
            FROM   XMLTable('/reply/ROWSET/ROW' PASSING v_xml_out COLUMNS AUTH_TYPE VARCHAR2(30), AUTH_STATUS VARCHAR2(1))
            WHERE  AUTH_STATUS = 'A';

            p_session_tan_active := 'N';
            p_request_session_id := v_request_session_id;

            /*
            ** determine CUSTOMER_NO from CONTACT_OBJID
            ** contact_objid should be unique
            */
            BEGIN
                SELECT CUSTOMER_NO
                  INTO p_customer_no
                  FROM EXT_CUSTOMER_ATTRIBUTES
                 WHERE ATTRIBUTE_TYPE = 'CUST_KIM'
                   AND KEY            = 'ContactObjID'
                   AND VALUE          = v_contact_objid;
            EXCEPTION
            WHEN NO_DATA_FOUND
            THEN
                 log_and_raise_error(
                     error.format(error.select_failed,
                                  userobject.get_description(userobject.table_code,
                                                             'EXT_CUSTOMER_ATTRIBUTES'),
                                  error.format(error.not_exists,v_contact_objid))
                 );
            WHEN TOO_MANY_ROWS
            THEN
                 log_and_raise_error(
                     error.format(error.select_failed,
                                  userobject.get_description(userobject.table_code,
                                                             'EXT_CUSTOMER_ATTRIBUTES'),
                                  error.format(error.not_unique,v_contact_objid))
                 );
            END;

            /* check if customer is allowed to use mobile TAN
            */
            SELECT
               EXTRACTVALUE(v_xml_out,
                            '/reply/ROWSET[@name="AUTH_METHODS"]/ROW[*]/AUTH_TYPE[text()="MTAN"]/../AUTH_STATUS')
            INTO
               v_auth_status
            FROM DUAL;

            IF NVL(v_auth_status, 'U') = 'A'
            THEN
                p_mtan_active := 'Y';
            ELSE
                p_mtan_active := 'N';
            END IF;
        ELSE
            error_handling;
        END IF;
    END authenticate;

    /*
    ** This external procedure has the following functions:
    ** p_tan equals NULL: request mobile TAN
    ** p_tan NOT NULL: activate session TAN
    ** It used the Calvin interface.
    */
    PROCEDURE
    session_tan_activate(
        p_request_session_id IN CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE,
        p_auth_method        IN  VARCHAR2,                                ---- Added Parameter as part of CR122 (71272)
        p_tan                IN VARCHAR2,
        p_success            OUT CHAR  -- Y or N
    )
    AS
        v_session_tan_status CHAR(1);
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_success := 'Y';
            RETURN;
        END IF;

        v_location := 'calvin.session_tan_activate';

        SELECT
            XMLCONCAT(
                XMLELEMENT("AUTH_METHOD", convert_to_http_char_set(p_auth_method)),           --- Added changes as part of CR122
                XMLELEMENT("SERVICE_OPERATION_MODE", CASE
                                                     WHEN p_tan IS NULL
                                                     THEN 'REQ_MTAN'
                                                     ELSE 'EXEC'
                                                     END),
                XMLELEMENT("TAN", convert_to_http_char_set(p_tan))
            )
        INTO v_xml_in
        FROM DUAL;

        calvin_query(
            p_request_service_name  =>  'MWSessionTanActivate',
            p_request_session_id    =>  p_request_session_id,
            p_calv_onfs_st          =>  '0',
            p_update_session_id     =>  FALSE,
            p_xml_in                =>  v_xml_in,
            p_xml_out               =>  v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            SELECT
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/SESSION_TAN_STATUS'))
            INTO
                v_session_tan_status
            FROM
                DUAL;

            p_success := 'Y';
            IF p_tan IS NOT NULL AND v_session_tan_status <> 'A'
            THEN
                p_success := 'N';
            END IF;
        ELSE
            error_handling;
        END IF;
    END session_tan_activate;

    /*
    ** This external procedure deactivates a session TAN
    */
    PROCEDURE
    session_tan_deactivate(
        p_request_session_id IN CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE,
        p_success            OUT CHAR  -- Y or N
    )
    AS
        v_session_tan_status CHAR(1);
    BEGIN
        IF parameter_tool.get_parameter_value('CALV_ONFS_ST') <> '0'
        THEN
            /*
            ** emergency system is active
            */
            p_success := 'Y';
            RETURN;
        END IF;

        v_location := 'calvin.session_tan_deactivate';
        v_xml_in   := NULL;

        calvin_query(
            p_request_service_name  =>  'MWSessionTanDeactivate',
            p_request_session_id    =>  p_request_session_id,
            p_calv_onfs_st          =>  '0',
            p_update_session_id     =>  FALSE,
            p_xml_in                =>  v_xml_in,
            p_xml_out               =>  v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            SELECT
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/SESSION_TAN_STATUS'))
            INTO
                v_session_tan_status
            FROM
                DUAL;

            IF v_session_tan_status = 'D'
            THEN
                p_success := 'Y';
            ELSE
                p_success := 'N';
            END IF;
        ELSE
            error_handling;
        END IF;
    END session_tan_deactivate;

    /*
     * Function pick best authentication Method from List
     */
    FUNCTION select_best_auth_method(p_auth_methods IN dbms_sql.varchar2_table)
    RETURN VARCHAR2
    IS
        TYPE t_map IS TABLE OF INTEGER INDEX BY VARCHAR2(30);
        v_map  t_map;
    BEGIN
        v_map('SECURE_CODE') := 0;
        v_map('SECURE_OTP')  := 0;
        v_map('MTAN')        := 0;
        v_map('TOKEN')       := 0;

        FOR i IN 1 .. p_auth_methods.count
        LOOP
            v_map(p_auth_methods(i)) := 1;
        END LOOP;

        RETURN CASE
            WHEN v_map('SECURE_CODE') = 1 THEN 'SECURE_CODE'
            WHEN v_map('SECURE_OTP') = 1  THEN 'SECURE_OTP'
            WHEN v_map('TOKEN') = 1       THEN 'TOKEN'
            WHEN v_map('MTAN') = 1        THEN 'MTAN'
            ELSE NULL END;
    END select_best_auth_method;

    /*
    ** This procedure creates a session token for a session id that has been returned
    ** by a successful login using OROMNTExeLogin service.
    */
    FUNCTION create_session_token(
        p_session_id  IN VARCHAR2,
        p_target_feid IN VARCHAR2)
    RETURN VARCHAR2
    IS
        v_xml_doc     XMLTYPE;
        v_xml_res_doc XMLTYPE;
        v_error_msg   VARCHAR2(16384);
    BEGIN
        SELECT XMLElement("OROMCreateSessionToken",
                   XMLConcat(
                       XMLElement("session_id",  convert_to_http_char_set(p_session_id)),
                       XMLElement("target_feid", convert_to_http_char_set(p_target_feid))
                   )
               )
        INTO v_xml_doc
        FROM DUAL;

        v_error_msg := calvin_soap.request(v_xml_doc, v_xml_res_doc);

        IF v_error_msg IS NOT NULL
        THEN
            IF v_error_msg = 'timeout'
            THEN RAISE_APPLICATION_ERROR(error.application_error_no, error.format(2321));
            ELSE RAISE_APPLICATION_ERROR(error.application_error_no, v_error_msg);
            END IF;
        END IF;

        v_xml_res_doc := v_xml_res_doc.extract('/oromxml/*');
        RETURN xmltools.get_string_val(v_xml_res_doc, '/OROMCreateSessionTokenResp/session_token/text()');
    END;

    /*
    ** This procedure submits login request to backend system and returns a
    ** session info record on success. This records holds the backend
    ** session id and customer no. and entitled that have been determined
    ** by backend from login data.
    */
    FUNCTION login(
        p_user_id IN VARCHAR2,
        p_pin     IN VARCHAR2,
        p_tan     IN VARCHAR2 DEFAULT NULL,
        p_realm   IN VARCHAR2 DEFAULT NULL,
        p_ip_adr  IN VARCHAR2 DEFAULT NULL)
    RETURN t_login_session_info
    IS
        v_xml_doc            XMLTYPE;
        v_xml_res_doc        XMLTYPE;
        v_web_session_id     VARCHAR2(  100);
        v_session_token      VARCHAR2(  100);
        v_error_msg          VARCHAR2(16384);
        v_login_session_info t_login_session_info;
    BEGIN
        SELECT XMLElement("OROMNTExeLogin",
            XMLConcat(
                XMLElement("userid", convert_to_http_char_set(p_user_id)),
                XMLElement("pin",    convert_to_http_char_set(p_pin)),
                XMLElement("tan",    convert_to_http_char_set(p_tan)),
                XMLElement("realm",  convert_to_http_char_set(p_realm)),
                XMLElement("ip_adr", convert_to_http_char_set(p_ip_adr))
            )
        )
        INTO v_xml_doc
        FROM DUAL;

        v_error_msg := calvin_soap.request(v_xml_doc, v_xml_res_doc);

        IF v_error_msg IS NOT NULL
        THEN
            IF v_error_msg = 'timeout'
            THEN RAISE_APPLICATION_ERROR(error.application_error_no, error.format(2321));
            ELSE RAISE_APPLICATION_ERROR(error.application_error_no, v_error_msg);
            END IF;
        END IF;

        -- Extract payload element, it's one under oromxml.
        v_xml_res_doc := v_xml_res_doc.extract('/oromxml/*');

        IF xmltools.get_number_val(v_xml_res_doc, '/OROMNTExeLoginResponse/restriction/text()') <> 0
        THEN
            RAISE_APPLICATION_ERROR(
                error.application_error_no,
                error.format(
                    80001,
                    v_xml_res_doc.extract('/OROMNTExeLoginResponse/restriction/text()').getStringVal()
                )
            );
        END IF;

        v_web_session_id := xmltools.get_string_val(v_xml_res_doc, '/OROMNTExeLoginResponse/session_id/text()');
        v_session_token  := create_session_token(v_web_session_id, parameter_tool.get_parameter_value('CALV_FEID'));

        calvin.reset_calvin_session_id();
        authenticate(
            p_session_token       => v_session_token,
            p_request_session_id  => v_login_session_info.session_id,
            p_crm_customer_no     => v_login_session_info.customer_no
        );

        v_login_session_info.entitled := xmltools.get_string_val(v_xml_res_doc, '/OROMNTExeLoginResponse/entitled/text()');

        SELECT AUTH_TYPE
        BULK COLLECT INTO v_login_session_info.auth_methods
        FROM   XMLTable(
            '/OROMNTExeLoginResponse/auth_methods/auth_method'
            PASSING
                v_xml_res_doc
            COLUMNS
                AUTH_TYPE   VARCHAR2(30) PATH 'auth_type',
                AUTH_STATUS VARCHAR2(1)  PATH 'auth_status'
        )
        WHERE  AUTH_STATUS = 'A';

        RETURN v_login_session_info;
    END login;


    /*
    ** This external procedure does the logout of a session.
    */
    PROCEDURE logout(
        p_request_session_id IN CUSTOMER_SESSION.REQUEST_SESSION_ID%TYPE,
        p_logout_code        OUT VARCHAR2
    )
    AS
        v_session_tan_status CHAR(1);
    BEGIN
        v_location := 'calvin.logout';
        v_xml_in   := NULL;

        calvin_query(
            p_request_service_name  =>  'logout',
            p_request_session_id    =>  p_request_session_id,
            p_calv_onfs_st          =>  parameter_tool.get_parameter_value('CALV_ONFS_ST'),
            p_update_session_id     =>  FALSE,
            p_xml_in                =>  v_xml_in,
            p_xml_out               =>  v_xml_out
        );

        IF (v_reply_error_code = '0')
        THEN
            SELECT
                TRIM(EXTRACTVALUE(v_xml_out, '/reply/LOGOUT_CODE'))
            INTO
                p_logout_code
            FROM
                DUAL;
        ELSE
            error_handling;
        END IF;
    END logout;
END calvin;
/
SHOW ERRORS
EXIT
