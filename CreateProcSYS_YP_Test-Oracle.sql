set serveroutput on 
--set echo on term on

create or replace procedure SYS.YP_TEST_ORACLE IS 
--- +============================================================================================================================================+
-- | Test-Oracle.sql
-- +============================================================================================================================================+
-- | Author: Martin Bruegger, Switzerland
-- | Name: 	 Martin Bruegger
-- | E-Mail: martin.bruegger@gmail.com
-- +--------------------------------------------------------------------------------------------------------------------------------------------+
-- | Description:
-- | Test-Oracle.sql is a SQL Developer User Defined Report or SQL-File FOR SQLAgain
-- | Performs Check_MK Oracle Monitor-Tests as in Watch-Oracle.ps1 defined, plus some others like DataGuard, Alertlog, Invalid Objects 
-- | It Displays the Result as a HTML Report in SQL Developer or any Browser
-- | Apart from the 1st Checks in "Data Guard" are all SELECTS dynamic Statements, because it runs also in a MOUNTED Physical Standby DB
-- +--------------------------------------------------------------------------------------------------------------------------------------------+
-- |
-- | Change History:
-- +-----------+------------+------------+------------------------------------------------------------------------------------------------------+
-- | Event     | Datum      | Autor      | Kommentar
-- +===========+============+============+======================================================================================================+
-- | created   | 2024/01/10 | mbruegger  | created
-- | modified  | 2024/01/26 | mbruegger  | Modifications according to codescan (PL/SQL and SQL Coding Guidelines, Trivadis) suggestions
-- | modified  | 2024/01/31 | mbruegger  | "where rownum" and "order by" G-3185: Never use ROWNUM at the same query level as ORDER BY.
-- | modified  | 2024/02/02 | mbruegger  | smaller font-size for "SQL Developer"
-- | modified  | 2024/06/18 | mbruegger  | DB startup-time added in header-section, DataGuard check when v$dataguard_config contains data 
-- | modified  | 2024/07/11 | mbruegger  | Comment cosmetics (after global change/replace action)
-- | modified  | 2024/07/17 | mbruegger  | TEST_DATA_GUARD: ignore v$database.switchover_status when in PDB
-- | modified  | 2024/07/19 | mbruegger  | Added TEST_CONTAINER_DATABASE and TEST_FLASHBACK_RECOVERY_AREA, css class='number'
-- | modified  | 2024/07/24 | mbruegger  | Added [PREP|TEST]_NEED_BACKUP; implemented as SYS.YP_TEST_ORACLE because DBMS_SCHEDULER and Credentials owned by SYS-User
-- | modified  | 2024/07/26 | mbruegger  | TEST_DATA_GUARD: added DGMGRL "show Configuration/show observer" (DBMS_SCHEDULER EXTERNAL_SCRIPT)
-- | modified  | 2024/07/30 | mbruegger  | Added PREP_NEED_BACKUP (split from TEST_NEED_BACKUP, fixed DBMS_SERVICES in DG Databases
-- | modified  | 2024/08/02 | mbruegger  | Added class textWarn: whenever a test contains more than one test, the causer for the alert is in textWarn colored
-- | modified  | 2024/08/26 | mbruegger  | CHECK_MK_LOCKS: exclude SYS.PLAN_TABLE$ in Monitor
-- | modified  | 2024/10/01 | mbruegger  | CHECK_MK_TABLESPACES: New Test "Critical: No Tempfiles for Temporary Tablespace found"
-- | modified  | 2025/01/09 | mbruegger  | CSS fixes - added  "div.box" for <PRE> and "file" tables, "nowrap" for date-columns (don't wrap timestamps). New l_MyTrackInfo
-- | modified  | 2025/01/10 | mbruegger  | 2.1.1 - Resulting HTML Code proofed/fixed according https://validator.w3.org/nu/#file
-- | modified  | 2025/01/16 | mbruegger  | 2.1.2 - HTML Footer now uses a P-Tag
-- | modified  | 2025/02/25 | mbruegger  | 2.1.3 - Date-Columns in "Outstanding Alerts" use class "nowrap" 
-- | modified  | 2025/03/21 | mbruegger  | 2.1.4 - "Invalid Objects" now includes UNUSABLE Indexes and Index-Partitions 
-- | modified  | 2025/05/13 | mbruegger  | 2.1.5 - "Invalid Objects" do not exclude SYS or SYSTEM objects
-- | modified  | 2025/05/15 | mbruegger  | 2.1.6 - PREP_NEED_BACKUP "need backup DAYS 2" Lists files requiring > 2 days of archived redo log files for complete recovery.
-- +-----------+------------+------------+------------------------------------------------------------------------------------------------------+
    l_MyTrackInfo   VARCHAR2(100) := 'SYS.YP_TEST_ORACLE, Version 2.1.6' ;
	l_ModuleName	VARCHAR2(100);							-- Query ModuleName (DBMS_APPLICATION_INFO.READ_MODULE). Use smaller font-sizes for "SQL Developer"
	l_ActionName	VARCHAR2(100);
	l_FontSize		VARCHAR2(4) := '12px' ;					-- Style: font-size for HTML elements
	l_TableWidth    VARCHAR2(20) := 'min-width: 800px;' ;	-- Style: table with (SQL Developer) or min-with (all other Browsers) 
    l_DBID          v$database.dbid%type;
	l_DBName        v$database.name%type;
	l_DBUName       v$database.db_unique_name%type;
	l_DBOpenMode	v$database.open_mode%type;	
	l_DBLogMode		v$database.log_mode%type;
	l_CDB			v$database.cdb%type;
	l_PlatformName  v$database.platform_name%type;
	l_ORACLE_HOME	VARCHAR2(100);
	l_CON_ID		PLS_INTEGER;							-- sys_context('USERENV','CON_ID') 1: connected to a CDB
	l_DBVersion		v$instance.version%type;	
	l_HostName      v$instance.host_name%type;
	l_InstanceName  v$instance.instance_name%type;	
	l_Date			VARCHAR2(40);
    l_Startup       VARCHAR2(20);
    l_DGConfig      PLS_INTEGER;
	l_TestFlag		PLS_INTEGER;
	l_RowCount      NUMBER;
	l_Comments      VARCHAR2(32767) ;
	l_CommentsPart	VARCHAR2(32767) ;
	-- used for DBMS_SCHEDULER call/fetch routines
	l_SchedError	BOOLEAN := FALSE ;						-- call to DBMS_SCHEDULER failed 
	l_SchedMsg      VARCHAR2(1000) ;						-- Error-Message from DBMS_SCHEDULER
	l_SchedScript   VARCHAR2(100);							-- Script to execute witch DBMS_SCHEDULER
	l_OutputFound 	PLS_INTEGER := 0;						-- got an output from DBMS_SCHEDULER Job ?
	l_LoopCount		PLS_INTEGER := 0;						-- loop/sleep to wait for async task to complete

	-- used for dynamic SQL Selects, for tables not existing in all databases (WINDAPRES tables, only NAB*)
	TYPE DynCursorType  IS REF CURSOR;
	c_DynCursor    	DynCursorType;
	l_DynRecord     varchar2(32767);
	l_DynTime       VARCHAR2(20);
	l_DynNumber		NUMBER;
	l_DynStatement  VARCHAR2(3000);


	--sys.DBMS_OUTPUT.ENABLE(null);

PROCEDURE PRINT_RESULT_COLUMN (in_TestFlag IN  PLS_INTEGER) is
BEGIN
	IF in_TestFlag = 0 THEN 
		sys.DBMS_OUTPUT.PUT_LINE('<TD class="bg_ok">OK</TD>');
	ELSIF in_TestFlag = 1 THEN      
		sys.DBMS_OUTPUT.PUT_LINE('<TD class="bg_warning">Warning</TD>');
	ELSE 
		sys.DBMS_OUTPUT.PUT_LINE('<TD class="bg_critical">Critical</TD>');
	END IF;
END PRINT_RESULT_COLUMN ;

PROCEDURE TEST_CONTAINER_DATABASE is
BEGIN 
	l_TestFlag := 0 ;
	l_Comments :=  '<TABLE> <TR><TD>Container ID</TD><TD>DB Name</TD><TD>Open Mode</TD><TD>Restricted </TD><TD>Open Time </TD><TD class=''number''>DB Size in GB</TD> </TR>' ;
	<<for_loop_CDB_1>>	
	FOR TS in (
		select con_id, name, open_mode, restricted, to_char(open_time,'YYYY/MM/DD HH24:MI:SS') open_time, to_char(total_size/(1024*1024*1024),'999,999,990.00') DB_sizeGB  from v$containers 
		) LOOP 
		IF (TS.con_id = 2 AND TS.open_mode != 'READ ONLY') OR (TS.con_id != 2 AND TS.open_mode != 'READ WRITE') THEN		-- PDB$SEED=READ ONLY, all other READ WRITE 
			l_TestFlag := 1 ;    
		END IF;
		l_Comments := l_Comments || '<TR><TD  class=''number''>'||TS.con_id ||'</TD><TD>'||TS.name ||'</TD><TD>'||TS.open_mode ||'</TD><TD>'||TS.restricted ||'</TD><TD>'||TS.open_time ||'</TD><TD class=''number''>'||TS.DB_sizeGB ||'</TD></TR>' ;	
		
	END LOOP for_loop_CDB_1 ;
	l_Comments := l_Comments || '</TABLE>Warning when Open Mode not READ WRITE (Exception: PDB$SEED open in READ ONLY)';
		
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>CDB</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');	
END TEST_CONTAINER_DATABASE ;

PROCEDURE TEST_FLASHBACK_RECOVERY_AREA is
	l_SpaceUsed BOOLEAN := FALSE ;
BEGIN
	l_TestFlag := 0 ;
	<<for_loop_FRA_1>>	
	FOR TS in (
		select name, to_char(space_limit/(1024*1024*1024),'990.00') space_limitGB, to_char(space_used/(1024*1024*1024),'999,990.00') space_usedGB, 
			((space_used-space_reclaimable)*100)/space_limit space_used_pct, to_char(space_reclaimable/(1024*1024*1024),'999,990.00') space_reclaimableGB from V$RECOVERY_FILE_DEST 
		) LOOP 
		IF    TS.space_used_pct > 95 THEN				-- Critical when space_used_pct > 95
			l_TestFlag := 2 ;
		ELSIF TS.space_used_pct > 90 THEN 				-- Warning when space_used_pct > 90 
			l_TestFlag := 1 ;    
		END IF;
		l_Comments := '<TABLE>';
		l_Comments := l_Comments || '<TR><TD>DB_RECOVERY_FILE_DEST				</TD><TD class=''number''>'||TS.name||'\'||l_DBUName            ||'   </TD></TR>' ;
		l_Comments := l_Comments || '<TR><TD>Space Limit          				</TD><TD class=''number''>'||TS.space_limitGB                   ||' GB</TD></TR>' ;
		l_Comments := l_Comments || '<TR><TD>Space Used           				</TD><TD class=''number''>'||TS.space_usedGB                    ||' GB</TD></TR>' ;
		l_Comments := l_Comments || '<TR><TD>Space Reclaimable    				</TD><TD class=''number''>'||TS.space_reclaimableGB             ||' GB</TD></TR>' ;
		l_Comments := l_Comments || '<TR><TD>% Used 							</TD><TD class=''number''>'||to_char(TS.space_used_pct,'990.0') ||'  %</TD></TR>' ;
		l_Comments := l_Comments || '</TABLE>Warning when % Used > 90, Critical when > 95'  ;
		IF TS.space_used_pct > 0 THEN
			l_SpaceUsed := TRUE ;
		END IF;
	END LOOP for_loop_FRA_1;
	
	<<for_loop_FRA_2>>	
	FOR TS in (
		select flashback_on, retention_target, to_char(oldest_flashback_time,'YYYY/MM/DD HH24:MI:SS') oldest_flashback_time, to_char(flashback_size/(1024*1024*1024),'999,990.00') flashback_sizeGB, 
			to_char(estimated_flashback_size/(1024*1024*1024),'999,990.00') estimated_sizeGB  from V$FLASHBACK_DATABASE_LOG, V$DATABASE
		) LOOP 
		IF TS.flashback_on = 'YES' THEN	
			l_Comments := l_Comments || '<br><br>Flashback Database Information   <TABLE>';
			l_Comments := l_Comments || '<TR><TD>DB_FLASHBACK_RETENTION_TARGET	            </TD><TD class=''number''>'||TS.retention_target       ||'</TD></TR>'  ;
			l_Comments := l_Comments || '<TR><TD>Oldest Flashback Time        	            </TD><TD class=''number''>'||TS.oldest_flashback_time  ||'</TD></TR>'  ;
			l_Comments := l_Comments || '<TR><TD>Current Size                 	            </TD><TD class=''number''>'||TS.flashback_sizeGB       ||' GB</TD></TR>'  ;
			l_Comments := l_Comments || '<TR><TD>Estimated Size needed for target retention </TD><TD class=''number''>'||TS.estimated_sizeGB       ||' GB</TD></TR>';
			l_Comments := l_Comments || '</TABLE>';
		END IF;		
	END LOOP for_loop_FRA_2;
	
	IF l_SpaceUsed THEN									-- skip this table when Recovery Area contains no data 
		l_Comments := l_Comments || '<br><br>Recovery Area Usage Information   <TABLE>';
		l_Comments := l_Comments || '<TR><TD>File Type 	</TD><TD class=''number''>% Space Used </TD><TD class=''number''>% Space Reclaimable </TD><TD class=''number''>Number of Files </TD></TR>' ;
		<<for_loop_FRA_3>>	
		FOR TS in (
			select file_type, to_char(percent_space_used,'990.0') percent_space_used_c , to_char(percent_space_reclaimable,'990.0') percent_space_reclaimable , number_of_files 
				from V$RECOVERY_AREA_USAGE where percent_space_used > 0 order by percent_space_used desc 
			) LOOP 
			l_Comments := l_Comments || '<TR><TD>'||TS.file_type ||'</TD><TD  class=''number''>'||TS.percent_space_used_c ||'</TD><TD class=''number''>'||TS.percent_space_reclaimable ||'</TD><TD class=''number''>'||TS.number_of_files ||'</TD> </TR>' ;			
		END LOOP for_loop_FRA_3;
		l_Comments := l_Comments || '</TABLE>';
	END IF;
		
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Recovery Area</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');	
END TEST_FLASHBACK_RECOVERY_AREA;

PROCEDURE PREP_DATA_GUARD is
BEGIN
l_SchedError := FALSE ;
	IF l_PlatformName like 'Microsoft Windows%' THEN
		l_SchedScript := '(echo show configuration; '|| chr(38) ||' echo show observer;) | '||l_ORACLE_HOME||'\bin\dgmgrl.exe /@'||l_DBName;
	ELSE
		l_SchedScript := 'printf "show configuration;\nshow observer;" | '||l_ORACLE_HOME||'/bin/dgmgrl /@'||l_DBName;
	END IF;
	DBMS_SCHEDULER.PURGE_LOG (  job_name =>  'DGMGRL_SHOW' );  
	BEGIN
		DBMS_SCHEDULER.CREATE_JOB(
			job_name            => 'DGMGRL_SHOW',
			job_type            => 'EXTERNAL_SCRIPT',
			job_action          => l_SchedScript,
			credential_name     => 'OS_CREDENTIAL',
			enabled             => true  );
		EXCEPTION
			WHEN OTHERS THEN
				l_SchedError := TRUE ;
				l_SchedMsg := SQLERRM ;
			BEGIN
				DBMS_SCHEDULER.DROP_JOB(					-- cleanup after CREATE_JOB failed    
					job_name            => 'DGMGRL_SHOW') ;
			EXCEPTION
			WHEN OTHERS THEN
				null;
			END ;
	END;	
END PREP_DATA_GUARD;

PROCEDURE TEST_DATA_GUARD is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	<<for_loop_DATA_GUARD_1>>	
	FOR TS in (
		select database, connect_identifier, dataguard_role, redo_source, enabled, status from V$DG_BROKER_CONFIG   
		) LOOP 
		IF l_RowCount = 0 THEN 
			l_Comments := 'Data Guard Broker Configuration:<br>' ;
			l_Comments := l_Comments||'<TABLE><TR><TH>Database</TH><TH>Connect Identifier</TH><TH>Database Role</TH><TH>Redo Source</TH><TH>DG Broker enabled</TH><TH>Status</TH></TR>' ;
		END IF;
		l_Comments := l_Comments ||'<TR><TD>'|| TS.database ||'</TD><TD>'|| TS.connect_identifier ||'</TD><TD>'|| TS.dataguard_role ||'</TD><TD>'|| TS.redo_source ||'</TD><TD>'|| TS.enabled ||'</TD><TD class=''number''>';
		IF TS.status > 0 THEN
			l_TestFlag := 2 ;
			l_Comments := l_Comments ||'<p class=''textWarn''>'||TS.status ||'</p></TD></TR>';			
		ELSE
			l_Comments := l_Comments ||TS.status ||'</TD></TR>';
		END IF;
		
		l_RowCount := l_RowCount +1;
	END LOOP for_loop_DATA_GUARD_1;
	IF l_RowCount > 0 THEN 
		l_Comments := l_Comments ||'</TABLE>' ;
		IF l_TestFlag  > 0 THEN
			l_Comments := l_Comments ||'Critical - Please verify above STATUS (View: V$DG_BROKER_CONFIG) <br>' ; 
		END IF ;
	END IF;
	
	l_Comments := l_Comments ||'<br>' ; 
	<<for_loop_DATA_GUARD_2>>
	FOR TS in (
		select database_role, protection_mode, protection_level, force_logging, flashback_on, dataguard_broker, switchover_status, fs_failover_status, fs_failover_mode,  
			fs_failover_observer_present, fs_failover_observer_host, fs_failover_current_target, fs_failover_threshold from V$DATABASE 
		) LOOP 
		l_Comments := l_Comments ||'<TABLE><TR><TH>Object</TH><TH>State</TH><TH>Description</TH></TR>' ;
        l_Comments := l_Comments ||'<TR><TD>DB Unique Name</TD><TD>'||l_DBUName||'</TD><TD>Globally unique name for the database';
		l_Comments := l_Comments ||'</TD><TR><TD>Database Role</TD><TD>'||TS.database_role||'</TD><TD>';
		IF l_DBOpenMode = 'READ WRITE' and TS.database_role = 'PRIMARY' THEN 															-- open Mode = READ WRITE and DB Role = PRIMARY
			l_Comments := l_Comments ||'OK' ;
		ELSIF l_DBOpenMode = 'MOUNTED' and TS.database_role = 'PHYSICAL STANDBY' THEN													-- OR open Mode = MOUNTED and DB Role = PHYSICAL STANDBY
			l_Comments := l_Comments ||'OK' ;
		ELSE
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Verify OPEN_MODE and/or DATABASE_ROLE.</p>' ;
			l_TestFlag := 2;
		END IF;
		l_Comments := l_Comments ||'</TD><TR><TD>Protection Mode</TD><TD>'||TS.protection_mode||'</TD><TD>';
		IF TS.protection_mode = TS.protection_level THEN 																				-- protection_mode=protection_level
			l_Comments := l_Comments ||'OK - Protection Level = configured Protection Mode' ;
		ELSE
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Protection Level ('||TS.protection_level||' is different to the configured Protection Mode.</p>' ;
			l_TestFlag := 2;
		END IF;
		
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Force Logging</TD><TD>'||TS.force_logging||'</TD><TD>';							-- Force Logging = YES
		IF TS.force_logging = 'YES' THEN 
				l_Comments := l_Comments ||'OK' ;
			ELSE 
				l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Force Logging should be ENABLED.</p>' ;
				l_TestFlag := 2;
		END IF;
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Flashback On</TD><TD>'||TS.flashback_on||'</TD><TD>';								-- Flashback On = YES
		IF TS.flashback_on = 'YES' THEN 
				l_Comments := l_Comments ||'OK' ;
			ELSE 
				l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Flashback should be ON.</p>' ;
				l_TestFlag := 2;
		END IF;
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Data Guard Broker</TD><TD>'||TS.dataguard_broker||'</TD><TD>';					-- Data Guard Broker = ENABLED
		IF TS.dataguard_broker = 'ENABLED' THEN 
			l_Comments := l_Comments ||'OK' ;
		ELSE 
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Data Guard Broker should be enabled.</p>' ;
			l_TestFlag := 2;
		END IF; 
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Observer present</TD><TD>'||TS.fs_failover_observer_present||'</TD><TD>';			-- Fast-Start Failover Observer Present = YES
		IF TS.fs_failover_observer_present = 'YES' THEN 
			l_Comments := l_Comments ||'OK' ;
		ELSE 
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - No Fast-Start Failover Observer connected to '||l_DBName||'.</p>' ;
			l_TestFlag := 2;
		END IF; 
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Observer Host</TD><TD>'||TS.fs_failover_observer_host||'</TD><TD>Host where the Observer is running.';	
		
		IF l_DBName = l_InstanceName THEN																							-- Switchover Status = TO STANDBY
			l_Comments := l_Comments ||'</TD></TR><TR><TD>Switchover Status</TD><TD>'||TS.switchover_status||'</TD><TD>';			-- but not for a PDB (l_DBName != l_InstanceName) See Doc ID 2910535.1 			
			IF TS.switchover_status = 'TO STANDBY' THEN 
				l_Comments := l_Comments ||'OK' ;
			ELSE 
				l_Comments := l_Comments ||'<p class=''textWarn''>Critical - switchover_status is not TO STANDBY.</p>' ;
				l_TestFlag := 2;
			END IF; 
		END IF;
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Fast-Start Failover Status</TD><TD>'||TS.fs_failover_status||'</TD><TD>';		-- Fast-Start Failover Status = SYNCHRONIZED
		IF TS.fs_failover_status = 'SYNCHRONIZED' THEN 
			l_Comments := l_Comments ||'OK' ;
		ELSE 
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Failover Status is not SYNCHRONIZED.</p>' ;
			l_TestFlag := 2;
		END IF; 
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Fast-Start Failover Mode</TD><TD>'||TS.fs_failover_mode||'</TD><TD>';			-- Fast-Start Failover Mode = ZERO DATA LOSS
		IF TS.fs_failover_mode = 'ZERO DATA LOSS' THEN 
			l_Comments := l_Comments ||'OK' ;
		ELSE 
			l_Comments := l_Comments ||'<p class=''textWarn''>Critical - Failover Mode is not ZERO DATA LOSS.</p>' ;
			l_TestFlag := 2;
		END IF; 
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Failover Target</TD><TD>'||TS.fs_failover_current_target||'</TD><TD>DB_UNIQUE_NAME of the standby that is the current fail-safe failover observer target standby for the Data Guard configuration';
		l_Comments := l_Comments ||'</TD></TR><TR><TD>Failover Threshold</TD><TD>'||TS.fs_failover_threshold||'</TD><TD>Time (in seconds) that the observer will attempt to reconnect with a disconnected primary before attempting fail-safe failover observer with the target standby';
		
	END LOOP for_loop_DATA_GUARD_2;	
    
	l_Comments := l_Comments ||'</TD></TR></TABLE><br>Last 30 Records from V$DATAGUARD_STATUS:' ;	
	l_CommentsPart := '1999/02/31 12:00:00' ;
	l_RowCount := 0 ;
	<<for_loop_DATA_GUARD_3>>
	FOR TS in (
		select b.time, b.message, b.severity from
		( select to_char(a.timestamp,'YYYY/MM/DD HH24:MI:SS') time, a.message, a.severity  from 
			(select timestamp, message, severity  from V$DATAGUARD_STATUS where timestamp > sysdate-7 order by timestamp desc) a where rownum < 31  ) b order by time asc
		) LOOP
		IF l_RowCount = 0 THEN 
			l_Comments := l_Comments ||'<DIV class="box"><TABLE class="file">' ;
		END IF;
		IF l_CommentsPart != TS.time THEN 
			l_Comments := l_Comments || '<TR><TD class="nowrap">'||TS.time ;
			l_CommentsPart := TS.time ;
		ELSE
			l_Comments := l_Comments || '<TR><TD>' ;
		END IF;
		l_Comments := l_Comments ||'</TD><TD>'||TS.message||'</TD><TD>'||TS.severity||'</TD></TR>' ;	
		l_RowCount := l_RowCount +1;
	END LOOP for_loop_DATA_GUARD_3; 
	IF l_RowCount > 0 THEN 
		l_Comments := l_Comments ||'</TABLE></DIV>' ;
	END IF;
	
	<<DATA_GUARD4_dgmgrl>>	
	IF l_CON_ID < 2 THEN		-- ORA-65040: operation not allowed from within a pluggable database. CON_ID 1 is the ROOT DB
		IF l_SchedError = TRUE THEN
			l_Comments := l_Comments ||'Call to DGMGRL using DBMS_SCHEDULER failed with Error :<br><TABLE class="file"><TR><TD>'||l_SchedMsg||'</TD></TR></TABLE>' ;
			
			l_TestFlag := 2;
		ELSE
			<<for_loop_DATA_GUARD_4>>
			l_LoopCount := 0 ;
			l_OutputFound := 0 ;
			LOOP 
				l_LoopCount := l_LoopCount +1;
				EXIT WHEN l_LoopCount > 30;			-- Run_Duration > 15 seconds
				select count(*) into l_OutputFound from user_scheduler_job_run_details where job_name = 'DGMGRL_SHOW' ;
				EXIT WHEN l_OutputFound > 0;
				
				DBMS_SESSION.SLEEP(0.5);
			END LOOP for_loop_DATA_GUARD_4 ;
			
			IF l_OutputFound>0 THEN
				<<for_loop_Need_Backup_2>>  
				FOR TS in (     
					select substr(output,instr(output,'DGMGRL ')) output
						from user_scheduler_job_run_details where log_id = (select max( log_id) from user_scheduler_job_run_details where job_name = 'DGMGRL_SHOW' ) 
					) LOOP 
					l_Comments := l_Comments || '<br><br>Output from DGMGRL <i>show configuration</i> and <i>show observer</i><br><br><DIV class="box"><PRE>'|| TS.output || '</PRE></DIV>';
				END LOOP for_loop_Need_Backup_2 ;
				DBMS_SCHEDULER.PURGE_LOG (  job_name =>  'DGMGRL_SHOW' );  
			ELSE
				l_Comments :=  'Test failed - waited '||(l_LoopCount-1)*0.5||' seconds for the DGMGRL Report - no success. Please check DBA_SCHEDULER_JOBS, DBA_SCHEDULER_JOB_RUN_DETAILS WHERE JOB_NAME = ''DGMGRL_SHOW'')' ;
			END IF ;
		END IF ;
	END IF;
	
	
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Data Guard</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>'); 
END TEST_DATA_GUARD ;

PROCEDURE CHECK_MK_LOCKS is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := NULL ;	
	l_DynStatement := 'select 	''<TR><TD>''||s.SID||''</TD><TD>''|| s.SERIAL#||''</TD><TD>''||s.MACHINE||''</TD><TD>''||s.PROGRAM||''</TD><TD>''||s.PROCESS||''</TD><TD>''||s.OSUSER||''</TD><TD>''||o.OWNER||''</TD><TD>''||o.OBJECT_NAME||''</TD></TR>'' 
						from SYS.V_$LOCKED_OBJECT A,  SYS.ALL_OBJECTS O, SYS.V_$SESSION s where s.SID in (select distinct BLOCKING_SESSION from  SYS.V_$SESSION where BLOCKING_SESSION_STATUS = ''VALID'' ) and A.OBJECT_ID = O.OBJECT_ID 
						and S.SID = A.SESSION_ID and O.OWNER IN (''CARBASE'',''MASTER'',''MATCHCODE'',''RF'',''WDRSONLINE'',''WINDAPRES'') union all 
						select distinct ''<TR><TD>''||s.SID||''</TD><TD>''|| s.SERIAL#||''</TD><TD>''||s.MACHINE||''</TD><TD>''||s.PROGRAM||''</TD><TD>''||s.PROCESS||''</TD><TD>''||s.OSUSER||''</TD><TD>''||o.OWNER||''</TD><TD>''||o.OBJECT_NAME||''</TD></TR>''
						from SYS.V_$LOCK l, SYS.V_$LOCKED_OBJECT lo, SYS.ALL_OBJECTS O, SYS.V_$SESSION s where l.TYPE = ''TX'' and l.LMODE = 6 and l.CTIME > 10800 and l.SID = lo.SESSION_ID and lo.OBJECT_ID = o.OBJECT_ID and l.SID = s.SID and o.OWNER||''.''
						||o.OBJECT_NAME not in (''SYS.PLAN_TABLE$'')'  ;  
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_LOCKS>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_LOCKS WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical, Locks found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>SID</TH><TH>Serial#</TH><TH>Machine</TH><TH>PROGRAM</TH><TH>Process</TH><TH>O/S User</TH><TH>Owner</TH><TH>Object Name</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_LOCKS;
	CLOSE c_DynCursor;
		
	IF l_TestFlag = 2 THEN 
		l_Comments := l_Comments || '</TABLE>' ;
		IF l_RowCount > 20 THEN 
			l_Comments := l_Comments ||'Found '||l_RowCount||' Locks, listed only the first 20.';
		ELSE 
			l_Comments := l_Comments ||'Found '||l_RowCount||' Locks.';
		END IF;
	ELSE 
		l_Comments := 'No Locks found.';
	END IF;
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK locks</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END CHECK_MK_LOCKS;

PROCEDURE CHECK_MK_LOGSWITCHES is 
BEGIN
	l_DynStatement := 'select count(*) logs from v$loghist where first_time > sysdate - 1/24' ;  
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_LOGSWITCHES>>
	LOOP
		FETCH c_DynCursor INTO l_DynNumber;
		EXIT fetch_loop_LOGSWITCHES WHEN c_DynCursor%NOTFOUND;
	END LOOP fetch_loop_LOGSWITCHES;
	CLOSE c_DynCursor;
	IF l_DynNumber > 100 THEN						-- Critical when log_switches > 100
		l_TestFlag := 2 ;						
	ELSIF l_DynNumber > 50 THEN 					-- Warning when log_switches > 50 
		l_TestFlag := 1 ;                  
	ELSE 
		l_TestFlag := 0 ; 
	END IF;
	l_Comments := '<TABLE><TR><TD>Logswitches from the last 1 Hour</TD><TD  class=''number''>'||l_DynNumber||'</TD></TR></TABLE>Warning when > 50, Critical when > 100'  ;

    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK logswitches</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END CHECK_MK_LOGSWITCHES ;

PROCEDURE CHECK_MK_PROCESSES is
BEGIN
	l_DynStatement := 'select i.value, p.processes from v$parameter i, (select count(*) processes from v$process) p where i.name = ''processes'''  ; 
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_PROCESSES>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord, l_DynNumber;
		EXIT fetch_loop_PROCESSES WHEN c_DynCursor%NOTFOUND;
	END LOOP fetch_loop_PROCESSES;
	CLOSE c_DynCursor;
	IF l_DynNumber > 450 THEN					-- Critical when processes > 450
		l_TestFlag := 2 ;						
	ELSIF l_DynNumber > 350 THEN 				-- Warning when processes > 350 
		l_TestFlag := 1 ;                  
	ELSE 
		l_TestFlag := 0 ; 
	END IF;
	l_Comments := '<TABLE><TR><TD>init.ora Parameter processes</TD><TD class=''number''>'||l_DynRecord||'</TD></TR>' ;
	l_Comments := l_Comments ||       '<TR><TD>Current DB Processes        </TD><TD class=''number''>'||l_DynNumber||'</TD></TR></TABLE>Warning when > 350, Critical when > 450'  ;
		
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK process</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END CHECK_MK_PROCESSES ;

PROCEDURE CHECK_MK_TABLESPACES is
BEGIN
    l_TestFlag := 0 ;
    l_RowCount := 0 ;
    l_Comments := NULL ;
	l_DynStatement := 'select ''<TR><TD>''||tablespace_name||''</TD><TD> DB File= ''''''||file_name||'''''', Online-Status=''||ONLINE_STATUS||''</TD><TD>Critical</TD></TR>'' from dba_data_files where ONLINE_STATUS not in (''SYSTEM'',''ONLINE'')' ;
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_TABLESPACES_1>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_TABLESPACES_1 WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical when Tablespace not ONLINE|READ ONLY
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>Tablespace Name</TH><TH>Reason</TH><TH>State</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_TABLESPACES_1;
	CLOSE c_DynCursor;
	IF l_RowCount > 20 THEN 
		l_Comments := l_Comments ||'<TR><TD>List truncated</TD><TD>Total '||l_RowCount||' DB Files ONLINE_STATUS not in (''ONLINE'',''SYSTEM'') found.</TD></TD></TD></TR>' ;
	END IF ;
		
    l_RowCount := 0 ;
		
	l_DynStatement := 'select ''<TR><TD>''||tablespace_name||''</TD><TD>Space used: ''||round(used_percent,1)||''</TD><TD>''||case when used_percent > 95 THEN ''Critical'' ELSE ''Warning'' END||''</TD></TR>'' ,' ||
						'case when used_percent > 95 THEN 2 ELSE 1 END from DBA_TABLESPACE_USAGE_METRICS where used_percent > 90' ;  
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_TABLESPACES_2>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord, l_DynNumber;
		EXIT fetch_loop_TABLESPACES_2 WHEN c_DynCursor%NOTFOUND;
		IF l_TestFlag < 2 THEN						-- Warning|Critical, Tablespace with Space deficit
			l_TestFlag := l_DynNumber;	        	-- l_DynNumber contains 1 or 2	
		END IF;					
		IF l_RowCount = 0 THEN 
			IF l_Comments is NULL THEN 
				l_Comments := '<TABLE><TR><TH>Tablespace Name</TH><TH>Reason</TH><TH>State</TH></TR>' ;
			END IF;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_TABLESPACES_2;
	CLOSE c_DynCursor;
	IF l_RowCount > 20 THEN 
		l_Comments := l_Comments ||'<TR><TD>List truncated</TD><TD>Total '||l_RowCount||' Tablespaces with Space Deficit found.</TD></TD></TD></TR>' ;
	END IF ;

	IF l_Comments is NULL THEN 		
        l_Comments := 'All DB Files ONLINE or SYSTEM, sufficient Space available.<br>' ;
	ELSE 
		l_Comments := l_Comments ||'</TABLE>';
	END IF;
	
	l_RowCount := 0 ;
	l_DynStatement := 'select 1 from (select count(*) "COUNT" from v$tempfile) ts where ts.COUNT = 0' ;
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_TABLESPACES_3>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_TABLESPACES_3 WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical when TEMPORARY TABLESPACE contains 0 TEMP-FILES
		l_RowCount := 1 ;
	END LOOP fetch_loop_TABLESPACES_3;
	CLOSE c_DynCursor;
	IF l_RowCount = 0 THEN
		l_Comments := l_Comments ||'Tempfiles for Temporary Tablespace found.<br>';
	ELSE
		l_Comments := l_Comments ||'Critical: No Tempfiles for Temporary Tablespace found.<br>';
	END IF;
	
	
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK tablespaces</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'Warning when Space used > 90%, Critical when Space used > 95% or DB File ONLINE_STATUS not in (''ONLINE'',''SYSTEM'') or no TEMPFILE found</TD></TR>');
END CHECK_MK_TABLESPACES ;

PROCEDURE CHECK_MK_CUSTD_JOBS is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := NULL ;
	l_DynStatement := 'select ''<TR><TD>''||SESSION_ID||''</TD><TD>''||min(to_char(SAMPLE_TIME,''YYYY/MM/DD HH24:MI''))||''</TD><TD>''||substr(max(SAMPLE_TIME)-min(SAMPLE_TIME),8,12)||''</TD><TD>'' 
						||USERNAME||''</TD><TD>''||PROGRAM||''</TD><TD>''||MACHINE||''</TD><TD>''||SQL_ID||''</TD><TD>''||COUNT(*)||''</TD></TR>'' line
						from ASHSTAT.L_ASH l, DBA_USERS u where l.USER_ID > 0 and l.USER_ID = u.USER_ID and SAMPLE_TIME > sysdate-1 group by SESSION_ID, SESSION_SERIAL#, USERNAME, PROGRAM, MACHINE, SQL_ID
						having  max(SAMPLE_TIME)-min(SAMPLE_TIME) > interval ''3'' hour and count(*) > 1000 and MAX(SAMPLE_TIME) > sysdate-1/24/60 order by line asc' ;  
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_CUSTD_JOBS>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_CUSTD_JOBS WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical, CUSTD long running Jobs found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>SID</TH><TH>Start Time</TH><TH>Duration</TH><TH>Username</TH><TH>PROGRAM</TH><TH>Machine</TH><TH>SQL ID</TH><TH>Count(*)</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_CUSTD_JOBS;

	IF l_TestFlag = 2 THEN 
		l_Comments := l_Comments || '</TABLE>' ;
		IF l_RowCount > 20 THEN 
			l_Comments := l_Comments ||'Found '||l_RowCount||' Jobs, listed only the first 20.';
		END IF;
	ELSE 
		l_Comments := 'No Jobs found.';
	END IF;

	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK Long Running Jobs</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');  
END CHECK_MK_CUSTD_JOBS ;

PROCEDURE CHECK_MK_CUSTD_WEBTRACKING is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := 'No Jobs found.' ;
	l_DynStatement := 'select round(24 * 60 * (sysdate - max(updstp)), 0) as v_minutes from MASTER.yt_tr_webtracking ';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_CUSTD_WEBTRACKING>>
	LOOP
		FETCH c_DynCursor INTO l_DynNumber;
		EXIT fetch_loop_CUSTD_WEBTRACKING WHEN c_DynCursor%NOTFOUND;
		IF l_DynNumber > 180 THEN 
			l_TestFlag := 2 ;						-- Critical, CUSTD Webtracking Waiting-Time > 180
		ELSIF l_DynNumber > 150 THEN 
			l_TestFlag := 1 ;						-- Warning, CUSTD Webtracking Waiting-Time > 150
		ELSE 
			l_TestFlag := 0;
		END IF;
		l_Comments := '<TABLE><TR><TD>Current Webtracking Waiting-Time in Minutes</TD><TD  class=''number''>'||l_DynNumber||'</TD></TR></TABLE>Warning when > 150, Critical when > 180'  ;
	END LOOP fetch_loop_CUSTD_WEBTRACKING;
	CLOSE c_DynCursor;
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK Webtracking </TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END CHECK_MK_CUSTD_WEBTRACKING ;

PROCEDURE CHECK_MK_CUSTD_DISK_WAITS is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := 'No waiting Sessions found.' ;
	l_DynStatement := 'SELECT count(*) FROM V$SESSION s WHERE s.machine like ''ZEUS\FW07%'' AND EVENT#=147'; -- Session ZEUS\FW07* is currently waiting for RFS (Remote File Server) WRITE 
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_CUSTD_DISK_WAITS>>
	LOOP
		FETCH c_DynCursor INTO l_DynNumber;
		EXIT fetch_loop_CUSTD_DISK_WAITS WHEN c_DynCursor%NOTFOUND;
		IF l_DynNumber > 3 THEN 
			l_TestFlag := 2 ;						-- Critical, CUSTD Disk-Waits > 3
		ELSIF l_DynNumber > 0 THEN 
			l_TestFlag := 1 ;						-- Warning, CUSTD Disk-Waits > 0
		ELSE 
			l_TestFlag := 0;
		END IF;
		l_Comments := '<TABLE><TR><TD>Current Disk-Waits from ZEUS\FW07% Sessions</TD><TD  class=''number''>'||l_DynNumber||'</TD></TR></TABLE>Warning when > 0, Critical when > 3'  ;
	END LOOP fetch_loop_CUSTD_DISK_WAITS;
	CLOSE c_DynCursor;
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK Disks waiting</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');  
END CHECK_MK_CUSTD_DISK_WAITS ;

PROCEDURE CHECK_MK_NABD_JOBS is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := 'No Jobs found.';
	l_DynStatement := 'select ''<TR><TD>''||SESSION_ID||''</TD><TD>''||min(to_char(SAMPLE_TIME,''YYYY/MM/DD HH24:MI''))||''</TD><TD>''||substr(max(SAMPLE_TIME)-min(SAMPLE_TIME),8,12)||''</TD><TD>'' 
						||USERNAME||''</TD><TD>''||PROGRAM||''</TD><TD>''||MACHINE||''</TD><TD>''||SQL_ID||''</TD><TD>''||COUNT(*)||''</TD></TR>'' line
						from ASHSTAT.L_ASH l, DBA_USERS u where l.USER_ID > 0 and l.USER_ID = u.USER_ID and SAMPLE_TIME > sysdate-1 and (PROGRAM not like ''WindapresSlave%'' and PROGRAM not like ''ORACLE.EXE (J%'')
						and MACHINE not like ''ZEUS\WDRS_%'' group by SESSION_ID, SESSION_SERIAL#, USERNAME, PROGRAM, MACHINE, SQL_ID HAVING   max(SAMPLE_TIME) - min(SAMPLE_TIME) > INTERVAL ''4'' HOUR  and COUNT(*) > 1200 and max(SAMPLE_TIME) > sysdate-1/24/60
						union all select ''<TR><TD>''||SESSION_ID||''</TD><TD>''||min(to_char(SAMPLE_TIME,''YYYY/MM/DD HH24:MI''))||''</TD><TD>''||substr(max(SAMPLE_TIME)-min(SAMPLE_TIME),8,12)||''</TD><TD>''
						||USERNAME||''</TD><TD>''||PROGRAM||''</TD><TD>''||MACHINE||''</TD><TD>''||SQL_ID||''</TD><TD>''||COUNT(*)||''</TD></TR>''
						from ASHSTAT.L_ASH l, DBA_USERS u where l.USER_ID > 0 and l.USER_ID = u.USER_ID and SAMPLE_TIME > sysdate-1 and (PROGRAM like ''WindapresSlave%'' and PROGRAM not like ''ORACLE.EXE (J%'') and MACHINE like ''ZEUS\WDRS_%''
						group by SESSION_ID, SESSION_SERIAL#, USERNAME, PROGRAM, MACHINE, SQL_ID HAVING   MAX (SAMPLE_TIME) - MIN (SAMPLE_TIME) > INTERVAL ''12'' HOUR  AND COUNT (*) > 3600 and MAX(SAMPLE_TIME) > sysdate-1/24/60 order by line asc' ;  
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_NABD_JOBS>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_NABD_JOBS WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical, NABD Long Running Jobs found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>SID</TH><TH>Start Time</TH><TH>Duration</TH><TH>Username</TH><TH>PROGRAM</TH><TH>Machine</TH><TH>SQL ID</TH><TH>Count(*)</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_NABD_JOBS;
	CLOSE c_DynCursor;

	IF l_TestFlag = 2 THEN 
		l_Comments := l_Comments || '</TABLE>' ;
		IF l_RowCount > 20 THEN 
			l_Comments := l_Comments ||'Found '||l_RowCount||' Jobs, listed only the first 20.';
		END IF;
	END IF;
			
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK Long Running Jobs</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');  
END CHECK_MK_NABD_JOBS ;

PROCEDURE CHECK_MK_NABD_WINDAPRES is
BEGIN
	l_TestFlag := 0 ;
	l_RowCount := 0 ;
	l_Comments := 'No Jobs found.';
	l_DynStatement := 'select  ''<TR><TD>''||to_char(sched.STARTTIME,''YYYY/MM/DD HH24:MI:SS'')||''</TD><TD>''||sched.JOBNR||''</TD><TD>''||job.NAME||''</TD><TD>''||mand.NAME||''</TD><TD>''||stat.JOBSTATUSREM||''</TD></TR>''
						from WDRSONLINE.YT_WDRS_JOB job left outer join WDRSONLINE.YT_WDRS_SCHEDULE sched on job.JOBNR = sched.JOBNR 
						left outer join WDRSONLINE.YT_WDRS_PROJECT proj on job.PROJEKTNR = proj.PROJEKTNR left outer join WDRSONLINE.YT_WDRS_MANDNT mand on proj.MANDANTNR = mand.MANDANTNR 
						left outer join WDRSONLINE.YT_WDRS_JOBSTATUS stat on job.STATUS = stat.JOBSTATUS where sched.JOBSTATUS = 0 and job.ISDELETED = 0 order by sched.STARTTIME desc';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_NABD_WINDAPRES>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_NABD_WINDAPRES WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;							-- Critical, NABD Windapres Jobs found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>Start Time</TH><TH>Job#</TH><TH>Name</TH><TH>Mandant</TH><TH>Status</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 20 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_NABD_WINDAPRES;
	CLOSE c_DynCursor;
	
	IF l_TestFlag = 2 THEN 
		l_Comments := l_Comments || '</TABLE>' ;
		IF l_RowCount > 20 THEN 
			l_Comments := l_Comments ||'Found '||l_RowCount||' Jobs, listed only the first 20.';
		END IF;
	END IF;
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Check_MK Windapres Jobs</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');  
END CHECK_MK_NABD_WINDAPRES;

PROCEDURE TEST_INVALID_OBJECTS is
BEGIN
	l_TestFlag := 0 ;
    l_RowCount := 0 ;
    l_Comments := 'No invalid Objects found.';
	                        
    l_DynStatement := 'select ''<TR><TD>''||OWNER||''</TD><TD>''||OBJECT_TYPE||''</TD><TD>''||OBJECT_NAME||''</TD><TD class=''''nowrap''''>''||to_char(CREATED,''YYYY/MM/DD HH24:MI:SS'')||''</TD><TD class=''''nowrap''''>''||to_char(LAST_DDL_TIME,''YYYY/MM/DD HH24:MI:SS'')||''</TD><TD>''||ERRORS||''</TD></TR>'' from
                        (select o.OWNER OWNER, o.OBJECT_TYPE OBJECT_TYPE, o.OBJECT_NAME OBJECT_NAME, CREATED, LAST_DDL_TIME, e.ERRORS
                            from dba_objects o 
                            left join ( select owner, name, type, listagg(line|| '' ''||text,''<br> '') within group(order by line) ERRORS from dba_errors group by owner, name, type) e
                                on e.owner = o.owner and e.name = o.object_name and e.type = o.object_type 
                            where o.STATUS != ''VALID'' 
                        union all
                        select i.owner, ''INDEX'', INDEX_NAME, o.created, o.last_ddl_time,  ''Index ''||i.owner||''.''||i.index_name||'' on ''||i.table_owner||''.''||i.table_name||'' is UNUSABLE''
                            from dba_indexes i
                            join dba_objects o on o.owner = i.owner and o.object_name = i.index_name and o.object_type = ''INDEX'' 
                            where i.status = ''UNUSABLE'' 
                        union all
                        select i.owner, ''INDEX'', i.INDEX_NAME, o.created, o.last_ddl_time,  ''Index ''||i.owner||''.''||i.index_name||'' Partition ''||p.partition_name||'' on ''||i.table_owner||''.''||i.table_name||'' is UNUSABLE''
                            from dba_ind_partitions p
                            join dba_indexes i on i.owner = p.index_owner and i.index_name = p.index_name
                            join dba_objects o on o.owner = p.index_owner and o.object_name =  p.index_name and o.subobject_name = p.partition_name
                            where p.status = ''UNUSABLE'' )
                        order by 1 asc' ;
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_INVALID_OBJECTS>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_INVALID_OBJECTS WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 1 ;						-- Warning, invalid Objects found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR><TH>Owner</TH><TH>Type</TH><TH>Name</TH><TH>Created</TH><TH>Last DDL Time</TH><TH>Line / Error</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 51 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_INVALID_OBJECTS;
	CLOSE c_DynCursor;
		
	IF l_TestFlag = 1 THEN 
		l_Comments := l_Comments || '</TABLE>' ;
		IF l_RowCount > 50 THEN 
			l_Comments := l_Comments ||'Found '||l_RowCount||' invalid Objects, listed only the first 50.';
		ELSE 
			l_Comments := l_Comments ||'Found '||l_RowCount||' invalid Objects.';
		END IF;
	END IF;		
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Invalid Objects</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END TEST_INVALID_OBJECTS;

PROCEDURE TEST_OUTSTANDING_ALERTS is
BEGIN
	l_TestFlag := 0 ;
    l_RowCount := 0 ;
    l_Comments := 'No Outstanding Alerts found.';
    	
	l_DynStatement := 'select ''<TR><TD class="nowrap">''||to_char(creation_time,''YYYY/MM/DD HH24:MI:SS'')||''</TD><TD>''||object_type||''</TD><TD>''||reason||''</TD><TD>''||suggested_action||''</TD></TR>'' from dba_outstanding_alerts order by creation_time ';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_OUTSTANDING_ALERTS_1>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_OUTSTANDING_ALERTS_1 WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 1 ;						-- Warning, Outstanding Alert found
		IF l_RowCount = 0 THEN 
			l_Comments := '<TABLE><TR class="textWarn"><TH>Time</TH><TH>Type</TH><TH>Reason</TH><TH>Suggested Action</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 51 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_OUTSTANDING_ALERTS_1;
	CLOSE c_DynCursor;
	
	IF l_RowCount > 0 THEN 
		l_Comments := l_Comments ||'</TABLE><br>' ;
	END IF;	
		
	l_RowCount := 0 ;	
	l_DynStatement := 'select ''<TR><TD class="nowrap">''||to_char(creation_time, ''YYYY/MM/DD HH24:MI:SS'')||''</TD><TD>''||object_type||''</TD><TD>''||reason||''</TD><TD>''|| decode(resolution,''N/A'','' '',resolution)||''</TD></TR>'' line from dba_alert_history where creation_time > sysdate-7 order by line desc ';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_OUTSTANDING_ALERTS_2>>
	LOOP
		FETCH c_DynCursor INTO l_DynRecord;
		EXIT fetch_loop_OUTSTANDING_ALERTS_2 WHEN c_DynCursor%NOTFOUND;
		IF l_RowCount = 0 THEN 
			l_Comments := l_Comments ||'<br>History-Records from DBA_ALERT_HISTORY from the last 7 Days<TABLE><TR><TH>Time</TH><TH>Type</TH><TH>Reason</TH><TH>Resolution</TH></TR>' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_RowCount < 21 THEN 
			l_Comments := l_Comments || l_DynRecord ; 
		END IF;
	END LOOP fetch_loop_OUTSTANDING_ALERTS_2;
	CLOSE c_DynCursor;
	
	IF l_RowCount > 0 THEN 
		l_Comments := l_Comments ||'</TABLE><br>' ;
	END IF;		
	
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Outstanding Alerts</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END TEST_OUTSTANDING_ALERTS ;

PROCEDURE TEST_ALERTLOG is
BEGIN
	l_TestFlag := 0 ;
    l_RowCount := 0 ;
    l_Comments := 'No Errors in Alertlog-File within last 7 days found.<br>';
	l_CommentsPart := '1999/02/31 12:00:00' ;
	l_DynStatement := 'select b.time, b.line from (select to_char(a.originating_timestamp,''YYYY/MM/DD HH24:MI:SS'') time, ''</TD><TD>''||a.message_text||''</TD><TD>''||decode(a.message_level,1,''Critical'',2,''Severe'',8,''Important'')||''</TD></TR>'' line  from 
						(select originating_timestamp, case when length(message_text) > 170 THEN substr(message_text,0,166)||'' ...'' ELSE message_text END message_text, message_level from v$diag_alert_ext where message_level < 16 and originating_timestamp > sysdate-7 order by originating_timestamp desc) a 
						where rownum < 21 ) b order by b.time, b.line asc';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_ALERTLOG_1>>
	LOOP
		FETCH c_DynCursor INTO l_DynTime, l_DynRecord;
		EXIT fetch_loop_ALERTLOG_1 WHEN c_DynCursor%NOTFOUND;
		l_TestFlag := 2 ;						-- Critical, Error in Alertlog found
		IF l_RowCount = 0 THEN 
			l_Comments := 'Records from V$DIAG_ALERT_EXT from the last 7 Days with MESSAGE_LEVEL Critical, Severe and Important:<br><DIV class="box"><TABLE class="file">' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_CommentsPart != l_DynTime THEN 
			l_Comments := l_Comments || '<TR class="textWarn"><TD class="nowrap">'||l_DynTime ;
			l_CommentsPart := l_DynTime ;
		ELSE
			l_Comments := l_Comments || '<TR><TD>' ;
		END IF;
		l_Comments := l_Comments ||l_DynRecord ;
	END LOOP fetch_loop_ALERTLOG_1;
	CLOSE c_DynCursor;
	
	IF l_RowCount > 0 THEN 
		l_Comments := l_Comments ||'</TABLE></DIV>' ;
	END IF;
	l_Comments := l_Comments ||'<br>Last 30 Records from the Alertlog-File:<br>';
	    
    l_RowCount := 0 ;
	l_CommentsPart := '1999/02/31 12:00:00' ;
	l_DynStatement := 'select b.time, b.line from (select to_char(a.originating_timestamp,''YYYY/MM/DD HH24:MI:SS'') time, ''</TD><TD>''|| a.message_text||''</TD></TR>'' line
						from ( select originating_timestamp, message_text from v$diag_alert_ext where originating_timestamp > sysdate-2 order by originating_timestamp desc ) a where rownum < 31 ) b order by b.time, b.line asc  ';
	OPEN c_DynCursor FOR l_DynStatement ;
	<<fetch_loop_ALERTLOG_2>>
	LOOP
		FETCH c_DynCursor INTO l_DynTime, l_DynRecord;
		EXIT fetch_loop_ALERTLOG_2 WHEN c_DynCursor%NOTFOUND;
		IF l_RowCount = 0 THEN
			l_Comments := l_Comments ||'<DIV class="box"><TABLE class="file">' ;
		END IF;
		l_RowCount := l_RowCount +1;
		IF l_CommentsPart != l_DynTime THEN
			l_Comments := l_Comments || '<TR><TD class="nowrap">'||l_DynTime ;
			l_CommentsPart := l_DynTime ;
		ELSE
			l_Comments := l_Comments || '<TR><TD>' ;
		END IF;
		l_Comments := l_Comments ||l_DynRecord ;
	END LOOP fetch_loop_ALERTLOG_2;
	CLOSE c_DynCursor;

	IF l_RowCount > 0 THEN
		l_Comments := l_Comments ||'</TABLE></DIV>' ;
	END IF;
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Alertlog</TH>');
	PRINT_RESULT_COLUMN(l_TestFlag) ;
	sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>');
END TEST_ALERTLOG;


PROCEDURE PREP_NEED_BACKUP is
BEGIN
--l_SchedScript := 'connect target /@'||l_DBName||'
--report need backup ;';
	DBMS_SCHEDULER.PURGE_LOG ( job_name => 'RMAN_NEED_BACKUP' );  
	DBMS_SCHEDULER.CREATE_JOB(
		job_name            => 'RMAN_NEED_BACKUP',
		job_type            => 'BACKUP_SCRIPT',
		job_action          => 'REPORT NEED BACKUP DAYS 2 ;',
		credential_name     => 'OS_CREDENTIAL',
		enabled             => false);					-- do not automatically run the job
	DBMS_SCHEDULER.SET_ATTRIBUTE( 						-- add first the DB_CREDENTIAL to connect to the DB (can't be done in the CREATE_JOB call)    
		name                => 'RMAN_NEED_BACKUP',
		attribute           => 'CONNECT_CREDENTIAL_NAME',
		value               => 'DB_CREDENTIAL');
	DBMS_SCHEDULER.ENABLE(								-- OK, ready to execute. The output is visible in output.user_scheduler_job_run_details
		name 				=> 'RMAN_NEED_BACKUP');
	EXCEPTION
        WHEN OTHERS THEN
			l_SchedError := TRUE ;
			l_SchedMsg := SQLERRM ;
		BEGIN
			DBMS_SCHEDULER.DROP_JOB(					-- cleanup after CREATE_JOB failed    
				job_name            => 'RMAN_NEED_BACKUP') ;
		EXCEPTION
        WHEN OTHERS THEN
			null;
		END ;
END PREP_NEED_BACKUP ;

PROCEDURE TEST_NEED_BACKUP is
BEGIN 
	l_TestFlag := 0 ;
    IF l_SchedError = TRUE THEN
        l_Comments :=  'Test failed - pre-requisites not met. Requires a <br>- Credential OS_CREDENTIAL for RMAN Calls<br>- Credential DB_CREDENTIAL to connect to the Database<br><br>DBMS_SCHEDULER.CREATE_JOB failed with Error:<br>' ;
        l_Comments := l_Comments ||'<DIV class="box"><PRE>'||l_SchedMsg||'</PRE></DIV>' ;
        l_TestFlag := 2;
    ELSE
        <<for_loop_Need_Backup_1>>
        LOOP 
            l_LoopCount := l_LoopCount +1;
            EXIT WHEN l_LoopCount > 120 ;			-- Run_Duration > 60 seconds
            select count(*) into l_OutputFound from user_scheduler_job_run_details where job_name = 'RMAN_NEED_BACKUP' ;
            EXIT WHEN l_OutputFound > 0;
            
            DBMS_SESSION.SLEEP(0.5);
        END LOOP for_loop_Need_Backup_1 ;
        
        IF l_OutputFound>0 THEN
            <<for_loop_Need_Backup_2>>  
            FOR TS in (     
                --select substr(output,instr(output,'using target database control')) output
				select output
                    from user_scheduler_job_run_details where log_id = (select max( log_id) from user_scheduler_job_run_details where job_name = 'RMAN_NEED_BACKUP' ) 
                ) LOOP 
				IF length(TS.output) > 700 THEN                -- if output_size of the RMAN Report need backup from 'connected to target'-EOF > 480 then it contains a list of files
                    l_TestFlag := 1 ;
					l_Comments :=  'Warning, RMAN <i>report need backup</i> lists DB-Files.' ;
				ELSE
					l_Comments :=  'No DB-Files in output from RMAN <i>report need backup</i> found.' ;
                end if;
                l_Comments := l_Comments || '<DIV class="box"><PRE>'|| TS.output || '</PRE></DIV>';
            END LOOP for_loop_Need_Backup_2 ;
            DBMS_SCHEDULER.PURGE_LOG (  job_name =>  'RMAN_NEED_BACKUP' );  
        ELSE
            l_Comments :=  'Test failed - waited '||(l_LoopCount-1)*0.5||' seconds for the RMAN Report - no success. Please check DBA_SCHEDULER_JOBS, DBA_SCHEDULER_JOB_RUN_DETAILS WHERE JOB_NAME = ''RMAN_NEED_BACKUP'')' ;
        END IF ;
    END IF ;
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TH>Need Backup</TH>');
    PRINT_RESULT_COLUMN(l_TestFlag) ;
    sys.DBMS_OUTPUT.PUT_LINE('<TD>'||l_Comments||'</TD></TR>'); 
END TEST_NEED_BACKUP ;

BEGIN
	DBMS_APPLICATION_INFO.read_module (   l_ModuleName, l_ActionName );
	IF l_ModuleName = 'SQL Developer' THEN
		l_FontSize := '9px' ;
		l_TableWidth := 'width: 800px;' ;
	END IF;
	select d.DBID, upper(sys_context('USERENV','DB_NAME')), sys_context('USERENV','DB_UNIQUE_NAME'), sys_context('USERENV','ORACLE_HOME'), substr(i.version_full,1,(instr(i.version_full,'.',1,2)-1)), to_char(i.startup_time,'YYYY/MM/DD HH24:MI:SS'),
		to_char(sysdate,'DL, HH24:MI'),  d.cdb, sys_context('USERENV','CON_ID'),  i.host_name, d.platform_name, upper(i.instance_name), d.open_mode, d.log_mode, (select count(*) from v$dataguard_config)
		into l_DBID, l_DBName, l_DBUName, l_ORACLE_HOME, l_DBVersion, l_Startup, l_Date, l_CDB, l_CON_ID, l_HostName, l_PlatformName, l_InstanceName, l_DBOpenMode, l_DBLogMode, l_DGConfig from v$database d, v$instance i ;


    sys.DBMS_OUTPUT.PUT_LINE('<!DOCTYPE html>');
    sys.DBMS_OUTPUT.PUT_LINE('<HTML lang="en">');
    sys.DBMS_OUTPUT.PUT_LINE('<HEAD>');
    sys.DBMS_OUTPUT.PUT_LINE('<meta charset="utf-8">');
    sys.DBMS_OUTPUT.PUT_LINE('<title>Test-Oracle '|| l_DBName ||'@'|| l_HostName || '</title>');
	sys.DBMS_OUTPUT.PUT_LINE('<STYLE>');
    sys.DBMS_OUTPUT.PUT_LINE('body                         {background-color: #2E2E2E}');
	sys.DBMS_OUTPUT.PUT_LINE('*                            {border-collapse: collapse;}');
    sys.DBMS_OUTPUT.PUT_LINE('h1, th, tr                   {color: #F2F2F2;}');
	sys.DBMS_OUTPUT.PUT_LINE('td, th                       {border: 1px solid #909090; text-align: left; font-family: arial; font-size: '||l_FontSize||'; padding-left: 5px; padding-right: 5px;}');
    sys.DBMS_OUTPUT.PUT_LINE('p                            {color: #CCCCCC; font-family: consolas; font-style: italic; font-size: 0.95em;}');
    sys.DBMS_OUTPUT.PUT_LINE('.header td, .header th       {border-style: none; text-align: left; font-family: arial; padding-top: 0px; padding-bottom: 0px;}');
    sys.DBMS_OUTPUT.PUT_LINE('.file                        {border-spacing: 0;}');
    sys.DBMS_OUTPUT.PUT_LINE('.file td                     {border: 0; font-family: consolas; padding-top: 0px; padding-bottom: 0px;}');
    sys.DBMS_OUTPUT.PUT_LINE('div.box                      {border-style: solid; border-width: thin; border-color:#dadce0; border-radius: 8px; padding: 10px 10px; background-color: #404040; font-family: consolas;}');
	sys.DBMS_OUTPUT.PUT_LINE('.comment table               {table-layout: fixed; '||l_TableWidth||'}');
    sys.DBMS_OUTPUT.PUT_LINE('td.comment, th.comment       {border: 1px solid #595959; font-family: consolas; font-size:  12px;}');
	sys.DBMS_OUTPUT.PUT_LINE('.number                      {text-align: right;}');  	
	sys.DBMS_OUTPUT.PUT_LINE('.textWarn                    {color: #FFAA00 ;}');  	
    sys.DBMS_OUTPUT.PUT_LINE('.nowrap                      {white-space: nowrap; width: 1%;}');  
    sys.DBMS_OUTPUT.PUT_LINE('.bg_ok                       {background-color: #00802b;}');  
    sys.DBMS_OUTPUT.PUT_LINE('.bg_warning                  {background-color: #ffaa00;}');  
    sys.DBMS_OUTPUT.PUT_LINE('.bg_critical                 {background-color: #cc5200;}');  
	sys.DBMS_OUTPUT.PUT_LINE('</STYLE>');
	sys.DBMS_OUTPUT.PUT_LINE('</HEAD>');
	sys.DBMS_OUTPUT.PUT_LINE('<BODY>');
	sys.DBMS_OUTPUT.PUT_LINE('<TABLE class="header"><TR><TH>Test-Oracle</TH><TD>Perform DB and Check_MK Monitor Tests</TD></TR><TR><TD>DB Name</TD><TH>'||l_DBName||'</TH></TR>');
	IF l_InstanceName != upper(l_DBUName) THEN 
		sys.DBMS_OUTPUT.PUT_LINE('<TR><TD>db_unique_name</TD><TD>'||l_DBUName||'</TD></TR>') ;
	END IF;
	IF l_CDB = 'YES' THEN 
		sys.DBMS_OUTPUT.PUT_LINE('<TR><TD>CDB Name</TD><TD>'||l_InstanceName||'</TD></TR>') ;
	END IF;
    sys.DBMS_OUTPUT.PUT_LINE('<TR><TD>DB ID</TD><TD>'||l_DBID||'</TD></TR>') ;
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TD>Host-Name</TD><TD>'||l_HostName||'    <i> ('||l_PlatformName||')</i></TD></TR><TR><TD>Open-Mode</TD><TD>'||l_DBOpenMode||'</TD></TR> <TR><TD>Log-Mode</TD><TD>'||l_DBLogMode||'</TD></TR>');
	sys.DBMS_OUTPUT.PUT_LINE('<TR><TD>Oracle-Version</TD><TD>'||l_DBVersion||'</TD></TR><TR><TD>Startup Date</TD><TD>'||l_Startup||'</TD></TR></TABLE><br>');
	sys.DBMS_OUTPUT.PUT_LINE('<DIV class="comment">');
	sys.DBMS_OUTPUT.PUT_LINE('<TABLE><TR><TH>Test Name</TH><TH>Result</TH><TH>Comments</TH></TR>');
	
	IF l_DBLogMode = 'ARCHIVELOG' THEN				-- skip Test-DBs without Backups
		PREP_NEED_BACKUP() ;						-- use DBMS_SCHEDULER to run a RMAN Report in async mode, get the result later in TEST_NEED_BACKUP
	END IF ;
	IF l_DGConfig > 0 AND l_CON_ID < 2 THEN 		-- if Data Guard on non-CDB (CON_ID=0) or CDB (CON_ID=1)  
		PREP_DATA_GUARD();							-- use DBMS_SCHEDULER to run a DGMGRL Report in async mode, get the result later in TEST_DATA_GUARD
	END IF;
	IF l_CON_ID = 1 THEN
		TEST_CONTAINER_DATABASE() ;
	END IF;
	TEST_FLASHBACK_RECOVERY_AREA();	
	CHECK_MK_LOCKS() ;
	CHECK_MK_LOGSWITCHES() ;
	CHECK_MK_PROCESSES() ;
	CHECK_MK_TABLESPACES () ;
	IF l_DBName = 'CUSTD' THEN 
		CHECK_MK_CUSTD_JOBS() ;
		CHECK_MK_CUSTD_WEBTRACKING() ;
		CHECK_MK_CUSTD_DISK_WAITS() ;
	END IF;
	IF l_DBName = 'NABD' THEN
		CHECK_MK_NABD_JOBS() ;
		CHECK_MK_NABD_WINDAPRES() ;
	END IF;
	TEST_INVALID_OBJECTS() ;
	TEST_OUTSTANDING_ALERTS() ;
	TEST_ALERTLOG() ;
	IF l_DBLogMode = 'ARCHIVELOG' THEN
		TEST_NEED_BACKUP() ;						-- part 2 of NEED_BACKUP - read the output from the DBMS_SCHEDULER Job
	END IF ;
	
	IF l_DGConfig > 0 THEN   
		TEST_DATA_GUARD();
	END IF;
   	
	sys.DBMS_OUTPUT.PUT_LINE('</TABLE>');
    sys.DBMS_OUTPUT.PUT_LINE('<BR><BR><P>'||l_MyTrackInfo||', '||l_Date||'</P>');
	sys.DBMS_OUTPUT.PUT_LINE('</DIV>');
	sys.DBMS_OUTPUT.PUT_LINE('</BODY>');
	sys.DBMS_OUTPUT.PUT_LINE('</HTML>');
	
	EXCEPTION
		WHEN no_data_found THEN
		sys.DBMS_OUTPUT.PUT_LINE('Exception no_data_found raised in Main of Test-Oracle.');
		
		WHEN OTHERS THEN
		sys.DBMS_OUTPUT.PUT_LINE('An error was encountered - '||SQLCODE||' - ERROR - '||SQLERRM);

END;
/
show error

declare
	sql_statement varchar2(1000);
begin
	for SS in (select USERNAME from dba_users where USERNAME in ('C##ADMIN','ADMIN') ) loop
		sql_statement := 'grant execute on sys.YP_TEST_ORACLE to '||ss.USERNAME ;
		dbms_output.put_line(sql_statement||' ;');
		execute immediate sql_statement ;
	end loop;
end ;
/

create or replace public synonym Test_Oracle for sys.YP_TEST_ORACLE ; 


set serveroutput on
DECLARE
	l_Credential_Found 	PLS_INTEGER := 0;
BEGIN
    <<for_loop_Test_Credential_1>>
    LOOP 
        select count(*) into l_Credential_Found from dba_credentials where credential_name = 'DB_CREDENTIAL' and owner = 'SYS' ;
        EXIT WHEN l_Credential_Found > 0;
        DBMS_CREDENTIAL.CREATE_CREDENTIAL(
            credential_name     => 'DB_CREDENTIAL',
            username            => 'sys',
            password            => 'Li55abon',
            database_role       => 'sysdba',
            enabled             => true,
            comments            => 'DB credentials for RMAN calls');
        END LOOP for_loop_Test_Credential_1 ;
        l_Credential_Found := 0 ;
    <<for_loop_Test_Credential_2>>
    LOOP 
        select count(*) into l_Credential_Found from dba_credentials where credential_name = 'OS_CREDENTIAL' and owner = 'SYS' ;
        EXIT WHEN l_Credential_Found > 0;
        DBMS_CREDENTIAL.CREATE_CREDENTIAL(
			credential_name    => 'OS_CREDENTIAL',
			username           => 'oracle-admin',
			password           => 'Kv9qRz5KZg',
			windows_domain     => 'ZEUS',
			enabled            => true,
			comments           => 'O/S credentials for RMAN calls');

        END LOOP for_loop_Test_Credential_2 ;
END ;
/

col owner 			format a5
col credential_name format a15
col username 		format a15
col windows_domain 	format a15
col comments 		format a35

select * from dba_credentials where credential_name in ('DB_CREDENTIAL','OS_CREDENTIAL') and owner = 'SYS' ;