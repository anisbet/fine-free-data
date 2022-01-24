#!usr/bin/env awk

## Create sql insert statements for discharged items in Symphony hist files.
BEGIN {
    FS="^";
    insertStatement = "INSERT OR IGNORE INTO discharges (DDate, Item) VALUES ";
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

    # And the item id which is found in the discharges line below.
    # E201901010005191831R ^S72EVFWSMTCHTCPL1^FEEPLCPL^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221115460540^CO1/1/2019,0:05^^O 
    item_id = substr($8,3,14);
    printf "('%s', %d)",transaction_date,item_id;
    if (count == -1){
        printf ",\n";
    }
    count++;
} 

END {
    print ";";
    print "END TRANSACTION;";
}