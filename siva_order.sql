
	/* This procedure implements order cancel for the FTNG front end. 
	 * Input is the /Ordr subtree of the request document, the new summary returned from FututreTrader core order implementation is returned
	 */

	    -- Extract order data from xmlDoc

        
		-- Cancel order by calling order_tool.order_cancel

	 