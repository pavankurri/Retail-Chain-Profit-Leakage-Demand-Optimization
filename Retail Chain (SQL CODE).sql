SELECT * FROM Customer_Master
SELECT * FROM Inventory_Daily
SELECT * FROM Product_Master
SELECT * FROM Promotions
SELECT * FROM Returns
SELECT * FROM Sales_Transactions
SELECT * FROM Vendor_Supply

use Project_2
--Top 10 profit leaking SKUs 
SELECT TOP 10
    s.SKU_ID,
    SUM(s.Selling_Price * s.Quantity)                  AS Gross_Revenue,
    SUM(s.Discount_Amount)                             AS Total_Discount,
    SUM(s.Quantity * p.Unit_Cost)                      AS Total_COGS,
    SUM(CASE WHEN r.Return_Status = 'Approved' 
        THEN r.Refund_Amount ELSE 0 END)               AS Total_Return_Loss,
    SUM(s.Selling_Price * s.Quantity)
        - SUM(s.Discount_Amount)
        - SUM(s.Quantity * p.Unit_Cost)
        - SUM(CASE WHEN r.Return_Status = 'Approved' 
            THEN r.Refund_Amount ELSE 0 END)           AS Net_Profit
FROM Sales_Transactions s
LEFT JOIN Product_Master p  ON s.SKU_ID = p.SKU_ID
LEFT JOIN Returns r         ON s.Order_ID = r.Order_ID
GROUP BY s.SKU_ID
ORDER BY Net_Profit ASC

--Stores with highest discount abuse 
SELECT TOP 10
    s.Store_ID,
    COUNT(s.Order_ID)                                      AS Total_Orders,
    SUM(s.Discount_Amount)                                 AS Total_Discount,
    SUM(s.Selling_Price * s.Quantity)                      AS Gross_Revenue,
    ROUND(
        SUM(s.Discount_Amount) * 100.0 
        / NULLIF(SUM(s.Selling_Price * s.Quantity), 0), 2
    )                                                      AS Discount_Rate_Pct,
    AVG(s.Discount_Amount)                                 AS Avg_Discount_Per_Order
FROM Sales_Transactions s
GROUP BY s.Store_ID
ORDER BY Discount_Rate_Pct DESC;


--Category-wise return contribution to loss 
SELECT 
    p.Category,
    COUNT(r.Return_ID)                                     AS Total_Returns,
    SUM(CASE WHEN r.Return_Status = 'Approved' 
        THEN r.Refund_Amount ELSE 0 END)                   AS Return_Loss,
    SUM(s.Selling_Price * s.Quantity)                      AS Gross_Revenue,
    ROUND(
        SUM(CASE WHEN r.Return_Status = 'Approved' 
            THEN r.Refund_Amount ELSE 0 END) * 100.0
        / NULLIF(SUM(s.Selling_Price * s.Quantity), 0), 2
    )                                                      AS Return_Loss_Pct,
    ROUND(
        COUNT(r.Return_ID) * 100.0 
        / NULLIF(SUM(COUNT(r.Return_ID)) OVER(), 0), 2
    )                                                      AS Contribution_To_Total_Returns_Pct
FROM Returns r
INNER JOIN Sales_Transactions s  ON r.Order_ID = s.Order_ID
INNER JOIN Product_Master p      ON s.SKU_ID = p.SKU_ID
WHERE r.Return_Status = 'Approved'
GROUP BY p.Category
ORDER BY Return_Loss DESC;


--Promotion-wise profitability ranking 
SELECT 
    pr.Promo_ID,
    pr.Promo_Type,
    pr.Target_Category,
    pr.Promo_Budget,
    COUNT(s.Order_ID)                                      AS Total_Orders,
    SUM(s.Selling_Price * s.Quantity)                      AS Gross_Revenue,
    SUM(s.Quantity * p.Unit_Cost)                          AS Total_COGS,
    SUM(s.Selling_Price * s.Quantity)
        - SUM(s.Discount_Amount)
        - SUM(s.Quantity * p.Unit_Cost)
        - SUM(CASE WHEN r.Return_Status = 'Approved' 
            THEN r.Refund_Amount ELSE 0 END)
        - pr.Promo_Budget                                  AS Net_Profit,
    ROUND(
        (SUM(s.Selling_Price * s.Quantity)
        - SUM(s.Discount_Amount)
        - SUM(s.Quantity * p.Unit_Cost)
        - SUM(CASE WHEN r.Return_Status = 'Approved' 
            THEN r.Refund_Amount ELSE 0 END)
        - pr.Promo_Budget) * 100.0
        / NULLIF(SUM(s.Selling_Price * s.Quantity), 0), 2
    )                                                      AS Net_Profit_Margin_Pct,
    RANK() OVER (ORDER BY 
        SUM(s.Selling_Price * s.Quantity)
        - SUM(s.Discount_Amount)
        - SUM(s.Quantity * p.Unit_Cost)
        - SUM(CASE WHEN r.Return_Status = 'Approved' 
            THEN r.Refund_Amount ELSE 0 END)
        - pr.Promo_Budget DESC
    )                                                      AS Profitability_Rank
FROM Promotions pr
LEFT JOIN Sales_Transactions s   ON pr.Promo_ID = s.Promo_ID
LEFT JOIN Product_Master p       ON s.SKU_ID = p.SKU_ID
LEFT JOIN Returns r              ON s.Order_ID = r.Order_ID
GROUP BY pr.Promo_ID, pr.Promo_Type, pr.Target_Category, pr.Promo_Budget
ORDER BY Profitability_Rank ASC;


--Vendor delay heatmap dataset 
SELECT 
    v.Vendor_ID,
    v.Store_ID,
    MONTH(v.Expected_Delivery_Date)                        AS Delivery_Month,
    DATENAME(MONTH, v.Expected_Delivery_Date)              AS Month_Name,
    COUNT(v.PO_ID)                                         AS Total_Orders,
    SUM(CASE WHEN v.SLA_Breach = 1 
        THEN 1 ELSE 0 END)                                 AS SLA_Breaches,
    ROUND(
        SUM(CASE WHEN v.SLA_Breach = 1 
            THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(v.PO_ID), 0), 2
    )                                                      AS SLA_Breach_Rate_Pct,
    AVG(v.Supply_Delay_Days)                               AS Avg_Delay_Days,
    MAX(v.Supply_Delay_Days)                               AS Max_Delay_Days,
    SUM(v.Supply_Delay_Days)                               AS Total_Delay_Days,
    SUM(v.Procurement_Cost)                                AS Total_Procurement_Cost
FROM Vendor_Supply v
GROUP BY 
    v.Vendor_ID,
    v.Store_ID,
    MONTH(v.Expected_Delivery_Date),
    DATENAME(MONTH, v.Expected_Delivery_Date)
ORDER BY 
    v.Vendor_ID,
    Delivery_Month ASC;


    --Stockout frequency per SKU-store 
    SELECT 
    i.SKU_ID,
    i.Store_ID,
    p.Category,
    p.Sub_Category,
    COUNT(i.Date)                                          AS Total_Days_Tracked,
    SUM(CASE WHEN i.Closing_Stock = 0 
        THEN 1 ELSE 0 END)                                 AS Stockout_Days,
    ROUND(
        SUM(CASE WHEN i.Closing_Stock = 0 
            THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(i.Date), 0), 2
    )                                                      AS Stockout_Frequency_Pct,
    SUM(CASE WHEN i.Closing_Stock <= i.Reorder_Level 
        THEN 1 ELSE 0 END)                                 AS Days_Below_Reorder,
    ROUND(
        SUM(CASE WHEN i.Closing_Stock <= i.Reorder_Level 
            THEN 1 ELSE 0 END) * 100.0
        / NULLIF(COUNT(i.Date), 0), 2
    )                                                      AS Below_Reorder_Pct,
    AVG(i.Closing_Stock)                                   AS Avg_Closing_Stock,
    MIN(i.Closing_Stock)                                   AS Min_Closing_Stock,
    AVG(i.Warehouse_Stock)                                 AS Avg_Warehouse_Stock
FROM Inventory_Daily i
LEFT JOIN Product_Master p       ON i.SKU_ID = p.SKU_ID
GROUP BY 
    i.SKU_ID,
    i.Store_ID,
    p.Category,
    p.Sub_Category
ORDER BY 
    Stockout_Days DESC,
    Stockout_Frequency_Pct DESC;


    --Customer cohorts (Month 0,1,2 repeat rate) 
WITH First_Purchase AS (
    SELECT 
        s.Customer_ID,
        MIN(CAST(s.Order_Date AS DATE))                    AS First_Order_Date,
        DATEFROMPARTS(
            YEAR(MIN(s.Order_Date)),
            MONTH(MIN(s.Order_Date)), 1
        )                                                  AS Cohort_Month
    FROM Sales_Transactions s
    WHERE s.Order_Status = 'Delivered'
    GROUP BY s.Customer_ID
),

Customer_Orders AS (
    SELECT 
        s.Customer_ID,
        CAST(s.Order_Date AS DATE)                         AS Order_Date,
        fp.Cohort_Month,
        DATEDIFF(MONTH, fp.Cohort_Month, s.Order_Date)     AS Month_Number
    FROM Sales_Transactions s
    INNER JOIN First_Purchase fp     ON s.Customer_ID = fp.Customer_ID
    WHERE s.Order_Status = 'Delivered'
),

Cohort_Size AS (
    SELECT 
        Cohort_Month,
        COUNT(DISTINCT Customer_ID)                        AS Total_Customers
    FROM First_Purchase
    GROUP BY Cohort_Month
),

Cohort_Retention AS (
    SELECT 
        co.Cohort_Month,
        co.Month_Number,
        COUNT(DISTINCT co.Customer_ID)                     AS Active_Customers
    FROM Customer_Orders co
    WHERE co.Month_Number IN (0, 1, 2)
    GROUP BY co.Cohort_Month, co.Month_Number
)

SELECT 
    cr.Cohort_Month,
    DATENAME(MONTH, cr.Cohort_Month) + ' ' 
        + CAST(YEAR(cr.Cohort_Month) AS VARCHAR)           AS Cohort_Label,
    cs.Total_Customers                                     AS Cohort_Size,
    cr.Month_Number,
    cr.Active_Customers,
    ROUND(
        cr.Active_Customers * 100.0 
        / NULLIF(cs.Total_Customers, 0), 2
    )                                                      AS Retention_Rate_Pct
FROM Cohort_Retention cr
INNER JOIN Cohort_Size cs            ON cr.Cohort_Month = cs.Cohort_Month
ORDER BY 
    cr.Cohort_Month ASC,
    cr.Month_Number ASC;


    --RFM scoring using SQL 
    WITH RFM_Base AS (
    SELECT
        s.Customer_ID,
        DATEDIFF(DAY, MAX(s.Order_Date), '2025-12-06')     AS Recency,
        COUNT(DISTINCT s.Order_ID)                         AS Frequency,
        SUM(s.Selling_Price * s.Quantity) 
            - SUM(s.Discount_Amount)                       AS Monetary
    FROM Sales_Transactions s
    WHERE s.Order_Status = 'Delivered'
    GROUP BY s.Customer_ID
),

RFM_Scores AS (
    SELECT
        Customer_ID,
        Recency,
        Frequency,
        Monetary,
        NTILE(5) OVER (ORDER BY Recency ASC)               AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency DESC)            AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary DESC)             AS M_Score
    FROM RFM_Base
),

RFM_Segments AS (
    SELECT
        Customer_ID,
        Recency,
        Frequency,
        ROUND(Monetary, 2)                                 AS Monetary,
        R_Score,
        F_Score,
        M_Score,
        CAST(R_Score AS VARCHAR) 
            + CAST(F_Score AS VARCHAR) 
            + CAST(M_Score AS VARCHAR)                     AS RFM_Cell,
        R_Score + F_Score + M_Score                        AS RFM_Total_Score,
        CASE
            WHEN R_Score = 5 AND F_Score = 5              THEN 'Champions'
            WHEN R_Score >= 4 AND F_Score >= 4            THEN 'Loyal Customers'
            WHEN R_Score >= 4 AND F_Score <= 2            THEN 'Recent Customers'
            WHEN R_Score >= 3 AND F_Score >= 3            THEN 'Potential Loyalists'
            WHEN R_Score = 5 AND F_Score = 1              THEN 'New Customers'
            WHEN R_Score <= 2 AND F_Score >= 4            THEN 'At Risk'
            WHEN R_Score <= 2 AND F_Score >= 2            THEN 'Hibernating'
            WHEN R_Score = 1 AND F_Score = 1              THEN 'Lost Customers'
            ELSE 'Need Attention'
        END                                                AS Customer_Segment
    FROM RFM_Scores
)

SELECT
    rs.*,
    c.City,
    c.Customer_Type
FROM RFM_Segments rs
LEFT JOIN Customer_Master c          ON rs.Customer_ID = c.Customer_ID
ORDER BY RFM_Total_Score DESC;
