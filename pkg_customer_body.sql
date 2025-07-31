

    /*
     * Split account number into branch-id and account number. Length of
     * branch-id is retrieved from parameter LEN_OF_VNDL. The part of the
     * number to be returned is identified by these constants.
     */
  

    /*
    ** get the right price_usage_indicator for a customer
    */
 
        --
        -- If no indicator is returned default to B, WP
        -- depending on buy/sell indicator.
        --
   

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
   
