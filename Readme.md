# Fine Free Overdue Data

Jan 5, 2022
This report and historical data pull will build a series of data that can be used to determine the trend of items going overdue,
how long customers are keeping them past the due date, and the number of customers that are doing so.
This in turn will be used to inform the overall report on the impact of removing overdue fees since June 2020.

## Business questions

* Are customers waiting longer for items?  (since the removal of overdue fees)
* Are more items being returned late? (since the removal of overdue fees)

# Purpose

**Null hypothesis:** Customers are not keeping materials past their due date since EPL went fine-free.
Special project parameters are that the data should be a list of counts per day.

The request is challenging because post-fine-free there are no bills created; the only hard evidence that a customer has exceeded the borrowing period for an item. Once the library went fine-free the only detectable way to determine if an item is overdue is to find it’s charge date, renew date (if any), and discharge date and compare those dates to the computed overdue date.

The overdue date is computed based on item type and profile described in the circulation map. Profiles at EPL only influence borrowing policy for system cards (i.e. LIBRARYUSE, DISCARD, STAFF) and institutionalized customers (i.e. MEDCERT, HOME, XDLOAN). Since system cards require special rules to control materials, and institutional customers checkout and return materials through controlled access, profiles can be ignored.

## Methodologies
The data will be aggregated by grouping item types by borrowing durations. For example blue-rays, CD, BOOK, and DVDs all have a 21 day borrowing period. A sum of all these types can form one line with the charge date and computed return date.

* Overdue bills appear in the history logs bill user entries which applies to both creating and paying a bill, so a simple count won't work.
*

## Data of interest
* Data should be collected from January 1, 2019 (20190101). This is a pre-COVID period that establishes normal full-fine behavior for customers.
* Fine-free date June 26, 2020 (20200626)
* End date of data collection June 14, 2021 (20210614)
* Deliverable is a CSV.


## Schema
CREATE TABLE charges (
    CDate TEXT,
    Item INT,
    DDate TEXT,
    primary key (CDate, Item)
);

# SQL
## Charges (CV)
zcat `gpn hist`/201901.hist.Z | grep -e 'S[0-9][0-9]CV' | awk -f CV.awk | sqlite3 hist.db

## Renewals (RV)
The SQL for the update is as follows.

update charges set DDate # "2019-01-21" where Item # 31221071226935;
Example of a renew transaction from history.

E201901010001471850R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLRIV^NQ31221119006877^IQInspirational L PBK^UO21221020690514^Fv200000^^O00102
E201901010002061849R ^S01RVFFBIBLIOCOMM^FcNONE^FEEPLRIV^NQ31221118808331^IQInspirational S PBK^UO21221020690514^Fv200000^^O00102

## Discharges
The history of a discharge is as follows.

E201901010005191831R ^S72EVFWSMTCHTCPL1^FEEPLCPL^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221115460540^CO1/1/2019,0:05^^O
E201901010005201831R ^S77EVFWSMTCHTCPL1^FEEPLCPL^FFSMTCHT^FcNONE^FDSIPCHK^dC6^NQ31221117295506^CO1/1/2019,0:05^^O

# SQL
Working drafts of SQL statements
Select all the item and charge dates where the discharge dates are less than the next charge date.
```sql
select Item, CDate, (select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1) from charges;
```

To compute the renews this query is based on the selection above.
```sql
select Item, CDate, (select RDate from renews where Item = charges.Item and RDate > charges.CDate order by RDate desc limit 1) from charges;
```

This query outputs the item, cdate, last discharged date, and the number of days between the charge and discharge date (if there is one).
```sql
select Item, CDate, (select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1), (JulianDay((select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1)) - JulianDay(CDate)) diff from charges;
```

Here is the query that combines the renews AND discharges above.
```sql
select Item, CDate, (select RDate from renews where Item = charges.Item and RDate > charges.CDate order by RDate desc limit 1) rdate, (select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1) dischg from charges;
```

I have updated the database to include a user table that lists the user ids and profiles, and an i_type table that includes the item ids and item types. 

With that you can get the profile of the user and the item type of the charged material.
```
select Item, (select Profile from users where User = c.User limit 1) profile, (select Type from i_types where Item = c.Item limit 1) item_type, CDate chg_date from charges as c;
```

To get the above AND the renew and discharge date we can do the following.
```sql
select 
Item, 
(select Profile from users where User = charges.User limit 1) profile, 
(select Type from i_types where Item = charges.Item limit 1) item_type, 
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
```

Now let's add the computed borrowing period to the mix.

```sql
select Item, (select Profile from users where User = charges.User limit 1) profile, (select Type from i_types where Item = charges.Item limit 1) item_type, CDate, (select RDate from renews where Item = charges.Item and RDate > charges.CDate order by RDate desc limit 1) rdate, (select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1) dischg, (JulianDay((select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1)) - JulianDay(CDate)) diff from charges;
```
The best way to tackle this is a view so the best view is with the charge date renew if any, and the discharge date.
```sql
create view overdues as select Item, (select Profile from users where User = charges.User limit 1) profile, (select Type from i_types where Item = charges.Item limit 1) item_type, CDate, (select RDate from renews where Item = charges.Item and RDate > charges.CDate order by RDate desc limit 1) rdate, (select DDate from discharges where Item = charges.Item and DDate > charges.CDate order by DDate limit 1) dischg from charges;
```
With that we should be able to conditionally select either the charge date OR the renew date and then compare that value with the discharge date.
```sql
select CDate, RDate, 
case when RDate != '' 
then 
RDate 
else 
CDate 
end last_active 
from charges;
```
Final Views
To create the views required we incorporate the above rough sql statements into the following final version.
```sql
create view od0_view as 
select 
Item, 
(select Profile from users where User = charges.User limit 1) Profile, 
(select Type from i_types where Item = charges.Item limit 1) Type, 
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
create view od1_view as
	select *, 
	(case when RDate != '' 
then 
RDate 
else 
CDate 
end) CRDate 
from od0_view;
```
Computing the Borrowing Range
Now let's add the computed borrowing period to the mix.

```sql
Create view as od2_view as
select 
Item, 
Profile, 
Type, 
CRDate, 
DDate, 
(JulianDay(DDate) - JulianDay(CRDate)) 
borrow_period 
from od1_view;
```
