
-- 1. Create Normalized Customer Demographics Dimension
SELECT DISTINCT
    customerID,
    gender,
    SeniorCitizen,
    Partner,
    Dependents
INTO dim_customers
FROM raw_telco_churn

ALTER TABLE dim_customers ADD CONSTRAINT PK_dim_customers PRIMARY KEY (customerID)

-- 2. Create Service Subscriptions Dimension
SELECT DISTINCT
    customerID,
    PhoneService,
    MultipleLines,
    InternetService,
    OnlineSecurity,
    OnlineBackup,
    DeviceProtection,
    TechSupport,
    StreamingTV,
    StreamingMovies,
    Active_Addons_Count
INTO dim_services
FROM raw_telco_churn

ALTER TABLE dim_services ADD CONSTRAINT PK_dim_services PRIMARY KEY (customerID)

-- 3. Create Account & Billing Fact Table
SELECT
    customerID,
    tenure,
    Tenure_Cohort,
    Contract,
    PaperlessBilling,
    PaymentMethod,
    MonthlyCharges,
    TotalCharges,
    Revenue_Tier,
    Churn,
    Churn_Flag
INTO fact_billing_churn
FROM raw_telco_churn

ALTER TABLE fact_billing_churn ADD CONSTRAINT PK_fact_billing PRIMARY KEY (customerID)

ALTER TABLE fact_billing_churn ADD CONSTRAINT FK_fact_customer FOREIGN KEY (customerID) REFERENCES dim_customers(customerID)

ALTER TABLE fact_billing_churn ADD CONSTRAINT FK_fact_service FOREIGN KEY (customerID) REFERENCES dim_services(customerID)

------------------------------------

-- QUERY 1: Executive Churn & Revenue at Risk Summary (MRR Lost)

SELECT 
    COUNT(customerID) AS Total_Customers,
    SUM(Churn_Flag) AS Churned_Customers,
    CAST(SUM(Churn_Flag) * 100.0 / COUNT(customerID) AS DECIMAL(5,2)) AS Churn_Rate_Pct,
    SUM(MonthlyCharges) AS Total_MRR,
    SUM(CASE WHEN Churn_Flag = 1 THEN MonthlyCharges ELSE 0 END) AS MRR_Lost,
    CAST(SUM(CASE WHEN Churn_Flag = 1 THEN MonthlyCharges ELSE 0 END) * 100.0 / SUM(MonthlyCharges) AS DECIMAL(5,2)) AS Revenue_Churn_Pct
FROM fact_billing_churn

-- QUERY 2: Cohort Retention & Cumulative Churn Risk using Window Functions

WITH CohortStats AS (
    SELECT 
        Tenure_Cohort,
        COUNT(customerID) AS Total_Users,
        SUM(Churn_Flag) AS Churned_Users,
        SUM(CASE WHEN Churn_Flag = 1 THEN MonthlyCharges ELSE 0 END) AS Lost_MRR
    FROM fact_billing_churn
    GROUP BY Tenure_Cohort
)
SELECT 
    Tenure_Cohort,
    Total_Users,
    Churned_Users,
    CAST(Churned_Users * 100.0 / Total_Users AS DECIMAL(5,2)) AS Cohort_Churn_Rate,
    Lost_MRR,
    SUM(Churned_Users) OVER (ORDER BY Tenure_Cohort) AS Cumulative_Churned_Users,
    CAST(Lost_MRR * 100.0 / SUM(Lost_MRR) OVER () AS DECIMAL(5,2)) AS Pct_Of_Total_Lost_MRR
FROM CohortStats
ORDER BY Tenure_Cohort

-- QUERY 3: Contract Type & Payment Method Friction Analysis (JOIN + RANK)

SELECT 
    b.Contract,
    b.PaymentMethod,
    COUNT(b.customerID) AS Customer_Count,
    SUM(b.Churn_Flag) AS Churned_Count,
    CAST(SUM(b.Churn_Flag) * 100.0 / COUNT(b.customerID) AS DECIMAL(5,2)) AS Churn_Rate_Pct,
    RANK() OVER (ORDER BY (SUM(b.Churn_Flag) * 1.0 / COUNT(b.customerID)) DESC) AS Risk_Rank
FROM fact_billing_churn b
JOIN dim_customers c ON b.customerID = c.customerID
GROUP BY b.Contract, b.PaymentMethod
HAVING COUNT(b.customerID) > 50
ORDER BY Risk_Rank

-- QUERY 4: Product Stickiness — Impact of Active Add-On Services on Churn

SELECT 
    s.InternetService,
    s.Active_Addons_Count,
    COUNT(b.customerID) AS Total_Subscribers,
    CAST(AVG(b.MonthlyCharges) AS DECIMAL(10,2)) AS Avg_Monthly_Bill,
    CAST(SUM(b.Churn_Flag) * 100.0 / COUNT(b.customerID) AS DECIMAL(5,2)) AS Churn_Rate_Pct
FROM dim_services s
JOIN fact_billing_churn b ON s.customerID = b.customerID
GROUP BY s.InternetService, s.Active_Addons_Count
ORDER BY s.InternetService, s.Active_Addons_Count