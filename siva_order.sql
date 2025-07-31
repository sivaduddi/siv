--- SIVA CODE
    
	/*
	 * The procedure implements order capture for FTNG frontend. 
	 * Input is the /Ordr subtree of the request document. 
	 * The procedure return a ftng_types.t_tx_result structure.
	*/
	FUNCTION order_capture(
	    p_order IN  XMLTYPE
	)
	RETURN t_tx_result
	IS
	    v_ordr                      ORDR%ROWTYPE;
        v_working_order             WORKING_ORDER%ROWTYPE;
        v_exchange_customer_order   EXCHANGE_CUSTOMER_ORDER%ROWTYPE;
        v_auth_no                   VARCHAR2(30);
        v_today            CONSTANT DATE := SYSDATE;
        v_ex_ante_ref_id            EX_ANTE_COST_CALCULATION.COST_ID%TYPE;
        v_nt_account                NT_ACCOUNT%ROWTYPE;
        v_nt_contract               NT_CONTRACT%ROWTYPE;    
        v_tx_result                 t_tx_result;
        v_messages                  usertype.REF_CURSOR;
        v_msg_details               usertype.REF_CURSOR;
		v_expiry_date               VARCHAR2(10);             
	BEGIN	
					
		v_order.CUSTOMER_DEPOT_NO 	                     := xmltools.get_string_val(p_order, '/Ordr/Acct/text()');
		v_order.CASH_ACCOUNT_NO 	                     := xmltools.get_string_val(p_order, '/Ordr/CAcct/text()');
		v_auth_no 	                                     := xmltools.get_string_val(p_order, '/Ordr/AuthNo/text()');
		v_exchange_customer_order.CONTRACT_KEY 	         := xmltools.get_string_val(p_order, '/Ordr/CntrK/text()');
		v_order.DEAL_TYPE 	                             := xmltools.get_string_val(p_order, '/Ordr/BSInd/text()');
		v_exchange_customer_order.OPEN_CLOSE_INDICATOR 	 := xmltools.get_string_val(p_order, '/Ordr/OCInd/text()');
		v_ordr.QUANTITY 	                             := xmltools.get_string_val(p_order, '/Ordr/Qty/text()');
		v_exchange_customer_order.COVERED_INDICATOR 	 := xmltools.get_string_val(p_order, '/Ordr/CovInd/text()');
		v_exchange_customer_order.LIMIT_ATTR_CODE 	     := xmltools.get_string_val(p_order, '/Ordr/LmtT/text()');
		v_exchange_customer_order.LIMIT1 	             := xmltools.get_string_val(p_order, '/Ordr/Lmt/text()');
		v_exchange_customer_order.STOP_LIMIT 	         := xmltools.get_string_val(p_order, '/Ordr/StpL/text()');
		v_exchange_customer_order.EXECUTION_INSTR_CODE 	 := xmltools.get_string_val(p_order, '/Ordr/Rstr/text()');
		v_exchange_customer_order.TRADING_RESTR_CODE 	 := xmltools.get_string_val(p_order, '/Ordr/Exp/text()');
		v_expiry_date                                    := xmltools.get_string_val(p_order, '/Ordr/ExpD/text()');
			IF v_expiry_date IS NOT NULL THEN
			   v_ordr.EXPIRY := TO_DATE(v_expiry_date || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS');			   
			END IF ;
		v_ex_ante_ref_id 	                             := xmltools.get_string_val(p_order, '/Ordr/ExAnte/text()');
		
	
	    SELECT *
        INTO   v_nt_account
        FROM   NT_ACCOUNT
        WHERE  ACCOUNT_NO       = v_order.CUSTOMER_DEPOT_NO
           AND AUTHORIZATION_NO = v_auth_no;
		   
		SELECT *
		INTO   v_nt_contract
		FROM   NT_CONTRACT
		WHERE  CONTRACT_KEY = v_exchange_customer_order.CONTRACT_KEY;   
		   
		xml_convert_func.get_trading_info(
			p_wkn              => v_nt_contract.WKN,
			p_deal_type        => v_order.DEAL_TYPE,
			p_order_type_code  => NULL,
			p_limit_attr_code  => v_order.LIMIT_ATTR_CODE,
			p_strategy_name    => NULL,
			p_exch_key         => v_nt_contract.EXCH_KEY,
			p_gateway          => 'OROM',
			p_text             => NULL,
			p_trading_place    => v_order.TRADING_PLACE,
			p_product_category => v_order.EQUITY_BASE_TYPE
        );

		sp_validated_order_capture(
			p_branch_id                 => ' ',
			p_block_order_number	    => NULL,
			p_order_type	            => ' ',
			p_bank_info_no	            => NULL,
			p_customer_no	            => v_nt_account.CUSTOMER_NO,
			p_constellation_id	        => v_nt_account.CONSTELLATION_ID,
            p_boega	                    => 'N',
            p_customer_depot_no	        => v_nt_account.ACCOUNT_NO,
			p_customer_depot_type	    => v_nt_account.ACCOUNT_TYPE,
            p_cash_account_no	        => v_nt_account.CASH_ACCOUNT_NO,
            p_cacc_curr	                => v_nt_account.CURR,
            p_interim_depot_no	        => NULL,
			p_interim_depot_type	    => NULL,
            p_interim_depot_no_cm	    => 'N',
            p_client_channel	        => 'H',
            p_captured_by	            => NULL,
			p_client					=> NULL,
            p_deal_type					=> v_order.DEAL_TYPE,
            p_wkn						=> v_nt_contract.WKN,
            p_quantity					=> v_order.QUANTITY,
            p_exch_key					=> v_nt_contract.EXCH_KEY,
            p_trading_model				=> 'F',
			p_trading_place				=> v_order.TRADING_PLACE,
            p_order_type_code			=> NULL,
            p_strategy_name				=> NULL,
            p_limit_attr_code			=> v_order.LIMIT_ATTR_CODE,
            p_limit1					=> v_order.LIMIT1,
            p_limit1_curr				=> v_nt_contract.CURR_TYP_COD,
            p_stop_limit				=> v_order.STOP_LIMIT,
			p_trading_restr_code	    => v_order.TRADING_RESTR_CODE,
            p_expiry	                => v_order.EXPIRY,
            p_closing	                => v_today,
            p_execution_instr_code	    => v_order.EXECUTION_INSTR_CODE,
            p_invoice_instr             => 'N',
            p_bo_check	                => 'N',
            p_already_dealt	            => 'N',
            p_fixed_price_trade	        => NULL,
            p_locally_processed	        => 'N',
            p_manual_processed	        => '1',
            p_trust_order	            => 'N',
			p_sales_text	            => ' ',
            p_trader_text	            => ' ',
            p_net_trade	                => 'N',
            p_customer_price	        => 0,
            p_par9wphg_mk	            => NULL,
            p_am_per_item	            => 'Y',
            p_bonification_percentage	=> NULL,
            p_bonification_amount	    => NULL,
            p_cost_center_perc	        => NULL,
            p_cost_center_amount	    => NULL,
            p_commission_percentage	    => NULL,
            p_commission_amount	        => NULL,
            p_own_expenses_percentage	=> NULL,
            p_own_expenses	            => NULL,
            p_fx_courtage_perc	        => NULL,
            p_fx_courtage_amount	    => NULL,
            p_cbf_fee_amount	        => NULL,
            p_notification_fee_amount	=> NULL,
            p_limit_fee	                => NULL,
			p_net_commission			=> 'N',
            p_net_fx_brokerage			=> 'N',
            p_net_brokerage				=> 'N',
            p_exemption_key				=> '0',
            p_custody_type				=> NULL,
            p_custody					=> NULL,
            p_deposit_attribute			=> NULL,
            p_piece_type				=> NULL,
            p_delivery_key				=> NULL,
            p_deviant_coupon			=> NULL,
            p_lock_1_date				=> NULL,
            p_lock_1_no					=> NULL,
            p_lock_1_type				=> NULL,
            p_lock_2_date				=> NULL,
            p_lock_2_no					=> NULL,
            p_lock_2_type				=> NULL,
            p_lock_3_date				=> NULL,
            p_lock_3_no					=> NULL,
            p_lock_3_type				=> NULL,
            p_fx_spread					=> NULL,
            p_value_offset				=> NULL,
            p_value_date				=> NULL,
            p_customer_ident_no			=> NULL,
            p_customer_ident_type		=> NULL,
            p_invoice_text				=> NULL,
            p_delivery_method			=> NULL,
            p_payment_method			=> NULL,
            p_manual_mod				=> NULL,
            p_manual_mop				=> NULL,
            p_order_channel				=> 'I',
            p_peak_size_qty				=> NULL,
            p_business_code				=> NULL,
            p_premium					=> NULL,
            p_bo_check_set_by_ritd		=> 'N',
            p_buy_ext_fonds_net_boni	=> 'N',
            p_brokerage_amount_changed	=> 'N',
            p_oft_flag					=> 'N',
            p_ext_ref_no				=> NULL,
            p_hvb_order_number			=> NULL,
            p_invoice_date				=> NULL,
            p_user_id					=> usersession.get_user,
            p_logon_user_id				=> NULL,
            p_internet_user				=> NULL,
            p_ticket					=> NULL,
            p_valid_from				=> v_today,
            p_equivalent				=> NULL,
            p_agreed_with				=> NULL,
            p_charging_type				=> NULL,
            p_charging_key				=> NULL,
            p_ipc_queue					=> NULL,
            p_manually_disposed			=> NULL,
            p_mq_msg_id					=> NULL,
            p_mq_reply_qmgr				=> NULL,
            p_mq_reply_queue			=> NULL,
            p_order_amount				=> NULL,
            p_order_amount_curr			=> NULL,
            p_forward_pricing			=> NULL,
			p_customer_class			=> '1',
            p_rule_id					=> NULL,
            p_rss_id					=> NULL,
            p_fx_fixing_date			=> NULL,
            p_deviant_account_no		=> NULL,
            p_deviant_cash_account_no 	=> NULL,
			p_list_id					=> NULL,
            p_salesman					=> usersession.get_user,
            p_gateway					=> 'OROM',
            p_contract_key				=> v_nt_contract.CONTRACT_KEY,
            p_open_close_indicator		=> v_exchange_customer_order.OPEN_CLOSE_INDICATOR,
            p_covered_indicator			=> v_exchange_customer_order.COVERED_INDICATOR,
            p_ex_ante_ref_id			=> v_ex_ante_ref_id,
            p_order_number				=> v_tx_result.order_no,
            p_last_change				=> v_tx_result.last_change,
            p_order_status				=> v_tx_result.order_status,
            p_new_summary				=> v_tx_result.summary,
            p_old_summary				=> NULL,
            p_messages					=> v_messages,
            p_msg_details				=> v_msg_details);
			
			RETURN v_tx_result;
			
	END order_capture;
		   
	/*
     * This procedure implements order change for the FTNG front end. 
     * Input is the /Ordr subtree of the request document, 
     * the new summary returned from FututreTrader core order implementation is returned.
    */
	
    FUNCTION order_change(
	    p_order IN  XMLTYPE
	)
    RETURN t_tx_result
	IS
	    v_ordr                      ORDR%ROWTYPE;
        v_working_order             WORKING_ORDER%ROWTYPE;
        v_exchange_customer_order   EXCHANGE_CUSTOMER_ORDER%ROWTYPE        
        v_tx_result                 t_tx_result;
        v_messages                  usertype.REF_CURSOR;
        v_msg_details               usertype.REF_CURSOR;
    BEGIN
	    -- Extract order data from xmlDoc
		
		v_order.CUSTOMER_DEPOT_NO 	                     := xmltools.get_string_val(p_order, '/Ordr/Acct/text()');
		v_order.CASH_ACCOUNT_NO 	                     := xmltools.get_string_val(p_order, '/Ordr/CAcct/text()');
		v_auth_no 	                                     := xmltools.get_string_val(p_order, '/Ordr/AuthNo/text()');
		v_exchange_customer_order.CONTRACT_KEY 	         := xmltools.get_string_val(p_order, '/Ordr/CntrK/text()');
		v_order.DEAL_TYPE 	                             := xmltools.get_string_val(p_order, '/Ordr/BSInd/text()');
		v_exchange_customer_order.OPEN_CLOSE_INDICATOR 	 := xmltools.get_string_val(p_order, '/Ordr/OCInd/text()');
		v_ordr.QUANTITY 	                             := xmltools.get_string_val(p_order, '/Ordr/Qty/text()');
		v_exchange_customer_order.COVERED_INDICATOR 	 := xmltools.get_string_val(p_order, '/Ordr/CovInd/text()');
		v_exchange_customer_order.LIMIT_ATTR_CODE 	     := xmltools.get_string_val(p_order, '/Ordr/LmtT/text()');
		v_exchange_customer_order.LIMIT1 	             := xmltools.get_string_val(p_order, '/Ordr/Lmt/text()');
		v_exchange_customer_order.STOP_LIMIT 	         := xmltools.get_string_val(p_order, '/Ordr/StpL/text()');
		v_exchange_customer_order.EXECUTION_INSTR_CODE 	 := xmltools.get_string_val(p_order, '/Ordr/Rstr/text()');
		v_exchange_customer_order.TRADING_RESTR_CODE 	 := xmltools.get_string_val(p_order, '/Ordr/Exp/text()');
		v_expiry_date                                    := xmltools.get_string_val(p_order, '/Ordr/ExpD/text()');
			IF v_expiry_date IS NOT NULL THEN
			   v_ordr.EXPIRY := TO_DATE(v_expiry_date || ' 23:59:59', 'YYYY-MM-DD HH24:MI:SS');			   
			END IF ;
		v_ex_ante_ref_id 	                             := xmltools.get_string_val(p_order, '/Ordr/ExAnte/text()');
		
		
	    -- Get order data from database (order as is before change)
		sp_order_select(
            p_order_no      => v_tx_result.order_no,
            p_branch_id     => ' ',
            p_order         => v_ordr,
            p_last_change   => v_tx_result.last_change
        );
        
        sp_working_order_select(
            p_order_no      => v_tx_result.order_no,
            p_branch_id     => ' ',
            p_working_order => v_working_order
        );
        
        sp_exch_customer_order_select(
            p_order_no                => v_tx_result.order_no,,
            p_branch_id               => ' ',
            p_version_no              => v_working_order.VERSION_NO
            p_exchange_customer_order => v_exchange_customer_order
        );

		-- Change order by calling sp_validated_order_change
		sp_validated_order_change(
            p_branch_id                => ' ',
            p_order_no                 => v_ordr.ORDER_NO,
            p_block_order_number       => v_working_order.BLOCK_ORDER_NO,
            p_order_type               => v_ordr.ORDER_TYPE,
            p_bank_info_no             => NULL,
            p_customer_depot_no        => v_ordr.CUSTOMER_DEPOT_NO,
            p_customer_depot_type      => v_ordr.CUSTOMER_DEPOT_TYPE,
            p_cash_account_no          => v_ordr.CASH_ACCOUNT_NO,
            p_cacc_curr                => v_ordr.CACC_CURR,
            p_interim_depot_no         => NULL,
            p_interim_depot_type       => NULL,
            p_interim_depot_no_cm      => NULL,
            p_client_channel           => v_ordr.CLIENT_CHANNEL,
            p_captured_by              => v_ordr.CAPTURED_BY,
            p_client                   => v_ordr.CLIENT,
            p_deal_type                => v_ordr.DEAL_TYPE,
            p_wkn                      => v_ordr.WKN,
            p_quantity                 => v_ordr.QUANTITY,
            p_exch_key                 => v_exchange_customer_order.EXCH_KEY,
            p_trading_model            => v_exchange_customer_order.TRADING_MODEL,
            p_trading_place            => v_ordr.TRADING_PLACE,
            p_order_type_code          => v_exchange_customer_order.ORDER_TYPE_CODE,
            p_strategy_name            => v_exchange_customer_order.STRATEGY_NAME,
            p_limit_attr_code          => v_exchange_customer_order.LIMIT_ATTR_CODE,
            p_limit1                   => v_exchange_customer_order.LIMIT1,
            p_limit1_curr              => v_exchange_customer_order.LIMIT1_CURR,
            p_stop_limit               => v_exchange_customer_order.STOP_LIMIT,
            p_trading_restr_code       => v_exchange_customer_order.TRADING_RESTR_CODE,
            p_expiry                   => v_ordr.EXPIRY,
            p_closing                  => v_ordr.CLOSING.,
            p_execution_instr_code     => v_exchange_customer_order.EXECUTION_INSTR_CODE,
            p_invoice_instr            => v_ordr.INVOICE_INSTR,
            p_bo_check                 => v_,
            p_already_dealt            => v_ordr.ALREADY_DEALT,
            p_locally_processed        => v_ordr.LOCALLY_PROCESSED,
            p_manual_processed         => v_ordr.MANUAL_PROCESSED,
            p_trust_order              => NULL,
            p_sales_text               => v_ordr.SALES_TEXT,
            p_trader_text              => v_ordr.TRADER_TEXT,
            p_net_trade                => v_ordr.NET_TRADE,
            p_customer_price           => v_ordr.CUSTOMER_PRICE,
            p_par9wphg_mk              => NULL,
            p_am_per_item              => 'Y',
            p_bonification_percentage  => NULL,
            p_bonification_amount      => NULL,
            p_cost_center_perc         => NULL,
            p_cost_center_amount       => NULL,
            p_commission_percentage    => NULL,
            p_commission_amount        => NULL,
            p_own_expenses_percentage  => NULL,
            p_own_expenses             => NULL,
            p_fx_courtage_perc         => NULL,
            p_fx_courtage_amount       => NULL,
            p_cbf_fee_amount           => NULL,
            p_notification_fee_amount  => NULL,
            p_limit_fee                => NULL,
            p_net_commission           => v_ordr.NET_COMMISSION,
            p_net_fx_brokerage         => v_ordr.NET_FX_BROKERAGE,
            p_net_brokerage            => v_ordr.NET_BROKERAGE,
            p_exemption_key            => NULL,
            p_custody_type             => v_ordr.CUSTODY_TYPE,
            p_custody                  => v_ordr.CUSTODY,
            p_deposit_attribute        => NULL,
            p_piece_type               => NULL,
            p_delivery_key             => NULL,
            p_deviant_coupon           => NULL,
            p_lock_1_date              => NULL,
            p_lock_1_no                => NULL,
            p_lock_1_type              => NULL,
            p_lock_2_date              => NULL,
            p_lock_2_no                => NULL,
            p_lock_2_type              => NULL,
            p_lock_3_date              => NULL,
            p_lock_3_no                => NULL,
            p_lock_3_type              => NULL,
            p_fx_spread                => NULL,
            p_value_offset             => NULL,
            p_value_date               => v_ordr.VALUE_DATE,
            p_customer_ident_no        => NULL,
            p_customer_ident_type      => NULL,
            p_invoice_text             => NULL,
            p_delivery_method          => NULL,
            p_payment_method           => NULL,
            p_manual_mod               => NULL,
            p_manual_mop               => NULL,
            p_order_channel            => order_tool.order_channel_ebrokerage,
            p_peak_size_qty            => NULL,
            p_business_code            => NULL,
            p_premium                  => NULL,
            p_bo_check_set_by_ritd     => NULL,
            p_buy_ext_fonds_net_boni   => NULL,
            p_brokerage_amount_changed => NULL,
            p_oft_flag                 => NULL,
            p_ext_ref_no               => v_ordr.EXT_REF_NO,
            p_valid_from               => v_ordr.VALID_FROM,
            p_equivalent               => v_ordr.EQUIVALENT,
            p_agreed_with              => NULL,
            p_charging_type            => NULL,
            p_charging_key             => NULL,
            p_ipc_queue                => NULL,
            p_manually_disposed        => NULL,
            p_mq_msg_id                => NULL,
            p_mq_reply_qmgr            => NULL,
            p_mq_reply_queue           => NULL,
            p_customer_id              => v_ordr.CUSTOMER_NO,
            p_constellation_id         => v_ordr.CONSTELLATION_ID,
            p_boega                    => NULL,
            p_order_amount             => NULL,
            p_order_amount_curr        => NULL,
            p_rss_id                   => v_ordr.RULE_SET_SPACE_ID,
            p_rule_id                  => v_ordr.RULE_ID,
            p_user_id                  => usersession.get_user,
            p_logon_user_id            => NULL,
            p_internet_user            => NULL,
            p_ticket                   => NULL,
            p_deviant_account_no       => NULL,
            p_deviant_cash_account_no  => NULL,
            p_salesman                 => v_ordr.SALESMAN,
            p_contract_key             => v_exchange_customer_order.CONTRACT_KEY,
            p_open_close_indicator     => v_exchange_customer_order.OPEN_CLOSE_INDICATOR,
            p_last_change              => v_ordr.LAST_CHANGE,
            p_version_no               => v_ordr.VERSION_NO,
            p_order_status             => v_ordr.ORDER_STATUS,
            p_quantity_done            => v_ordr.QUANTITY_DONE,
            p_quantity_open            => v_ordr.QUANTITY_OPEN,
            p_average_price            => v_ordr.AVERAGE_PRICE,
            p_average_price_inc        => v_ordr.AVERAGE_PRICE_INCL,
            p_new_summary              => v_tx_result.summary,
            p_old_summary              => NULL,
            p_messages                 => v_messages,
            p_msg_details              => v_msg_details
        );
		
		-- Set tx result properties and return
		v_tx_result.order_status := v_ordr.ORDER_STATUS;
        v_tx_result.last_change  := v_ordr.LAST_CHANGE;
        
        RETURN v_tx_result;
    
	EXCEPTION
        WHEN OTHERS
        THEN
            error.log_message (
                p_location => 'order_change',
                p_message  => SQLERRM || CHR(10) || dbms_utility.format_error_backtrace,
                p_severity => error.severity_error,
                p_file     => 'server.log');
            ftng_Exception := new FTNGException(sql_code => SQLCODE, message => SQLERRM);
            ftng_Exception.throw();
	END;
	
	/* This procedure implements order cancel for the FTNG front end. 
	 * Input is the /Ordr subtree of the request document, the new summary returned from FututreTrader core order implementation is returned
	 */
	 
	FUNCTION order_cancel(
	    p_order IN  XMLTYPE
    )
	RETURN t_tx_restult
	IS
	    v_tx_result      t_tx_result;
    BEGIN
	    -- Extract order data from xmlDoc
		v_tx_result.order_no    := xmltools.get_num_val(p_order, '/Ordr/@id');
   		v_tx_result.last_change := xmltools.get_num_val(p_order, '/Ordr/LstC/text()');
        
		-- Cancel order by calling order_tool.order_cancel
		order_tool.order_cancel (
            p_order_no     => v_tx_result.order_no,
            p_branch_id    => ' ',
            p_user_id      => usersession.get_user,
            p_last_change  => v_tx_result.last_change,
            p_order_status => v_tx_result.order_status,
            p_new_summary  => v_tx_result.summary
        );
       
       RETURN v_tx_result;
	END;
/

SHOW ERROR
EXIT

	 