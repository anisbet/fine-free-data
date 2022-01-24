#!usr/bin/env awk

## Create sql insert statements for extracting checkouts (charges) from Symphony hist files.
BEGIN {
    FS="^";
    insertStatement = "INSERT OR IGNORE INTO charges (CDate, Item, User) VALUES ";
    print "BEGIN TRANSACTION;"
    print insertStatement;
    count = -1;
    # The Test ILS seems to need smaller chunks.
    max_query_lines = 150;
    default_date = "1900-01-01";
}


# For any non-empty entry print the values to insert to the Items table.
/^E[0-9]/ {
    if (count == max_query_lines) {
        count = 0;
        printf ";\nEND TRANSACTION;\nBEGIN TRANSACTION;\n" insertStatement "\n";
    } 
    if (count > 0){
        printf ",\n";
    }
    
    transaction_date = default_date;
    # Format the date into a ISO standard date: YYYY-MM-DD. 
    year = substr($1,2,4);
    month= substr($1,6,2);
    day  = substr($1,8,2);
    transaction_date = sprintf("%d-%02d-%02d",year,month,day);

    # And the item id which is found in the charge line below.
    # E201901010512021843R ^S02CVFFADMIN^FEEPLMNA^FcNONE^FWADMIN^NQ31221118056873^UOILS-MISSING^OM^^O00074 
    item_id = substr($6,3,14);
    user_id = substr($7,3,14);
    printf "('%s', %d, '%s')",transaction_date,item_id,user_id;
    if (count == -1){
        printf ",\n";
    }
    count++;
} 

END {
    print ";";
    print "END TRANSACTION;";
}