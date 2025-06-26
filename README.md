# UserDefinedReports
Oracle SQL Developer / User Defined Reports

Test-Oracle produces a user friendly HTML Report with different Tests. Results (OK/Warning/Critical colored in green, yellow or red), and details. 

Procedure SYS.YP_TEST_ORACLE is required - use file CreateProcSYS_YP_Test-Oracle.sql to create it. Test-Oracle.sql is the alternate method to call the report (with SQLAgain)

It uses dynamic SQL, RMAN need backup and DGMGRL reports are included (executed with DBMS_SCHEDULER). It is even able to query a MOUNTED PHYSICAL STANDBY DataGuard instance.
![image](https://github.com/user-attachments/assets/ad45fe00-deb2-473b-8584-8f28f1ddaada)

DBA_RECYCLEBIN lists Objects placed in Recyclebin and generates Statements to restore all related Objects (Indexes, Trigger) for a selected Table 
![image](https://github.com/user-attachments/assets/2123d26e-e938-4623-81ec-a185c7e8c17b)


