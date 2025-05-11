--creating table e_commerce;
drop table if exists e_commerce;
create table e_commerce(
Invoice_No varchar (7),
Stock_Code varchar (12),
Description varchar(255),
Quantity int,
Invoice_Date text,
Unit_Price float,
Customer_ID varchar(7),
Country varchar(50)
);
-- changing invoice_date from text to timestamp
ALTER TABLE e_commerce 
ADD COLUMN InvoiceDateNew TIMESTAMP;

UPDATE e_commerce 
SET InvoiceDateNew = TO_TIMESTAMP(Invoice_Date, 'MM/DD/YYYY HH24:MI');

ALTER TABLE e_commerce 
DROP COLUMN Invoice_Date;

ALTER TABLE e_commerce 
RENAME COLUMN InvoiceDateNew TO Invoice_Date;



-- data preparation and cleaning
SELECT 
    SUM(CASE WHEN Customer_ID IS NULL THEN 1 ELSE 0 END) AS Missing_Customers,
    SUM(CASE WHEN Invoice_Date IS NULL THEN 1 ELSE 0 END) AS Missing_Dates,
    SUM(CASE WHEN Unit_Price IS NULL THEN 1 ELSE 0 END) AS Missing_Prices


DELETE FROM e_commerce 
WHERE Customer_ID IS NULL OR Unit_Price <= 0 ;


update e_commerce
set quantity = abs(quantity)
where quantity < 0;

delete from e_commerce
where quantity = 0;

-- checking duplicate transactions
select invoice_no,stock_code,count(*)
from e_commerce
group by invoice_no,stock_code
having count(*)>1;

-- deleting duplicate transactions
delete from e_commerce
where invoice_no in (select invoice_no 
from (select invoice_no,row_number()over(partition by invoice_no,stock_code
order by invoice_date) as rn
from e_commerce) as t
where rn > 1);

--EDA
--key metrics

--  Distribution of Total Sales:
SELECT 
    SUM(quantity * unit_price) AS Total_Sales,
    COUNT(DISTINCT invoice_no) AS Total_Transactions,
    COUNT(DISTINCT customer_id) AS Unique_Customers
FROM e_commerce;

-- Average Purchase Size (refers to the average value of each transaction)
select invoice_no,round(sum(quantity * unit_price::decimal),2) as purchase_amount
from e_commerce
group by invoice_no
order by purchase_amount desc;

-- overall average purchase size,
SELECT 
    round(AVG(Purchase_Amount),2) AS Average_Purchase_Size
FROM (
    SELECT 
        invoice_no, 
        SUM(quantity * unit_price::decimal) AS Purchase_Amount
    FROM e_commerce
    GROUP BY invoice_no
) t;



-- Calculate Recency, Frequency, and Monetary Value
with rfm_data as
(select customer_id,
max(invoice_date) as last_purchase_date,
count(invoice_no)as frequency,
sum(quantity * unit_price::decimal ) as monetory
from e_commerce
where customer_id is not null
group by customer_id
)
select customer_id,
extract(day from (current_date - last_purchase_date)) AS recency_in_days,
frequency,
monetory
from rfm_data;

--Assign Scores using NTILE(5)
 -- RFM Scores (5 is best, 1 is worst)
WITH scored_data AS (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
		ntile(5)over( order by recency asc) as recency_score,
		ntile(5)over(order by frequency desc) as frequency_score,
		ntile(5)over(order by monetary desc) monetary_score
		from (select customer_id,
extract(days from current_date-max(invoice_date)) as recency,
count(invoice_no)as frequency,
sum(quantity * unit_price::decimal ) as monetary
from e_commerce
where customer_id is not null
group by customer_id)as rfm_data)
		
select customer_id,recency,frequency,monetary,
recency_score,frequency_score,monetary_score,
concat(recency_score,frequency_score,monetary_score)as rfm_score
from scored_data;

-- Segment Customers Based on RFM Score

WITH scored_data AS (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
		ntile(5)over( order by recency asc) as recency_score,
		ntile(5)over(order by frequency desc) as frequency_score,
		ntile(5)over(order by monetary desc) monetary_score
		from (select customer_id,
extract(days from current_date-max(invoice_date)) as recency,
count(invoice_no)as frequency,
sum(quantity * unit_price::decimal ) as monetary
from e_commerce
where customer_id is not null
group by customer_id)as rfm_data)
select customer_id,recency,frequency,monetary,
recency_score,frequency_score,monetary_score,
concat(recency_score,frequency_score,monetary_score)as rfm_score,
CASE 
        WHEN rfm_score LIKE '555' THEN 'Best Customers'
        WHEN rfm_score LIKE '5%' THEN 'Loyal Customers'
        WHEN rfm_score LIKE '%5%' THEN 'Big Spenders'
        WHEN rfm_score LIKE '%1' THEN 'At-Risk Customers'
		 WHEN rfm_score LIKE '1%' THEN 'New Customers'
        ELSE 'Promising Customers'
    END AS customer_segment
	FROM (
    SELECT 
        customer_id,
        recency,
        frequency,
        monetary,
        recency_score,
        frequency_score,
        monetary_score,
        CONCAT(recency_score, frequency_score, monetary_score) AS rfm_score
    FROM scored_data
) AS final_data;

