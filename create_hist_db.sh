#!/bin/bash
WORKING_DIR='/software/EDPL/Unicorn/EPLwork/anisbet/Research/Quincy'
HIST_DATE_RANGE="20190101,20210630"
DB_DEV='hist.db'
DB_CMD="sqlite3 $DB_DEV"
[ -f "$DB_DEV" ] && echo "drop table charges;" | $DB_CMD
[ -f "$DB_DEV" ] && echo "drop table renews;" | $DB_CMD
[ -f "$DB_DEV" ] && echo "drop table discharges;" | $DB_CMD
### sqlite3 table creation
echo "creating database tables and importing 'users' and 'i_types'"
$DB_CMD <<END_SQL
create table if not exists charges (
    CDate TEXT,
    Item INT,
    User TEXT,
    primary key (CDate,Item)
);
create table if not exists renews (
    RDate TEXT,
    Item INT,
    primary key (RDate,Item)
);
create table if not exists discharges (
    DDate TEXT,
    Item INT,
    primary key (DDate,Item)
);
create table if not exists users (
	User TEXT, 
	Profile TEXT
);
create table if not exists i_types (
	Item INT,
	Type TEXT
);
.mode csv
.import users_profile.csv users
.import item_types.csv i_types
create index if not exists idx_users on users (User);
create index if not exists idx_types on i_types (Item);
.exit
END_SQL

## Run command to scrape the charges.
echo "starting to import data from hist files"
for hist_file in $(whichhistfiles.pl -d $HIST_DATE_RANGE ); do
	echo "$hist_file charges"
 	zcat $hist_file | grep -e 'S[0-9][0-9]CV' | awk -f CV.awk | $DB_CMD
done

## Run command to update charges (if exists) with renewal dates.
for hist_file in $(whichhistfiles.pl -d $HIST_DATE_RANGE); do
	echo "$hist_file renewals"
 	zcat $hist_file | grep -e 'S[0-9][0-9]RV' | awk -f RV.awk | $DB_CMD
done

## Run command to insert discharge dates. 
for hist_file in $(whichhistfiles.pl -d $HIST_DATE_RANGE); do
	echo "$hist_file discharges"
 	zcat $hist_file | grep -e 'S[0-9][0-9]EV'| awk -f EV.awk | $DB_CMD
done
echo "done"
echo "building views"

$DB_CMD <<END_SQL
CREATE INDEX IF NOT EXISTS idx_cv_item ON charges (Item);
CREATE INDEX IF NOT EXISTS idx_cv_user ON charges (User);
CREATE INDEX IF NOT EXISTS idx_cv_cdate_user ON charges (CDate, User);
CREATE INDEX IF NOT EXISTS idx_rv_rdate_item ON renews (RDate, Item);
CREATE INDEX IF NOT EXISTS idx_ev_ddate_item ON discharges (DDate, Item);
CREATE VIEW od0_view as
select
Item,
(select Profile from users where User = charges.User limit 1)
Profile,
(select Type from i_types where Item = charges.Item limit 1) 
Type,
CDate,
(select RDate
from renews
where Item = charges.Item
and
RDate > charges.CDate
and
RDate <= (select DDate
from discharges
where Item = charges.Item
and
DDate > charges.CDate
order by DDate limit 1)
order by RDate desc limit 1)
RDate,
(select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1)
DDate
from charges;
-- 
-- Add a column of the last renew date or the original charge date if none
-- 
CREATE VIEW od1_view as
select *,
(case when RDate != ''
then
RDate
else
CDate
end) CRDate
from od0_view;
-- 
-- Compute borrowing period in another view
-- 
create view od2_view as
select 
Item, 
Profile, 
Type, 
CRDate, 
DDate, 
(JulianDay(DDate) - JulianDay(CRDate)) 
CDays 
from od1_view;
-- 
-- Output data here down
-- 
.headers on
.mode csv
.output quincy_21day_videos.csv
-- 
-- Query of all the 21 day video types for customers.
-- 
select *, 
(case when CDays <= 21.0 then 'N' else 'Y' end) Overdue
from od2_view 
where Profile in (
'EPL_ADULT',
'EPL_JUV',
'EPL_NOVIDG',
'EPL_JNOVG',
'EPL_TEMP',
'EPL_SELF',
'EPL_METRO',
'EPL_UAL',
'EPL_JUV05',
'EPL_JUV10',
'EPL_STAFF'
)
and
Type in (
'DVD21',
'JCD',
'JDVD21',
'JVIDEO21',
'VIDEO21',
'BLU-RAY21',
'JBLU-RAY21'
)
and
DDate <= '2021-06-14';
.output quincy_all_data.csv
select * from od2_view 
where Profile in (
'EPL_ADULT',
'EPL_JUV',
'EPL_NOVIDG',
'EPL_JNOVG',
'EPL_TEMP',
'EPL_SELF',
'EPL_METRO',
'EPL_UAL',
'EPL_JUV05',
'EPL_JUV10',
'EPL_STAFF'
)
and
DDate <= '2021-06-14';
.exit
END_SQL
echo "database created"
