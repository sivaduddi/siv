

    /*
    ** Checks, if stock is greater than zero for closing order
    ** sp_fo_position_closable_test
    ** hard check
    */

    /*
    ** Checks, if the order's validity is within the customer's futures trading ability
    ** sp_bt_exp_date_fdc_exp_test
    ** hard check
    */



    /*
    ** Checks, if the order's expiry date is within a year starting today
    ** sp_fo_exp_date_valid_date_test
    ** hard check
    */


    /*
    ** Checks, if the order is coverable
    ** sp_fo_order_covered_test
    ** hard check
    */
   

    -- validation #100 already reserved by ORDER_VAL_CHECK_FUNCTIONS

    /*
    ** Checks, if stop limit and limit are set correctly
    ** hard check
    */
  
    /*
    ** Checks, if spanish account has a closing or an option
    ** hard check
    */
  

    /*
    ** Checks the risk profile of the current user
    ** hard check
    */
   


    /*
    ** Margin checks on an account.
    ** Validation messages: 40150-40153
    */
   

        -- Extended attributes of account and margin account are needed. Therefore we need
        -- the margin account no. first.
 