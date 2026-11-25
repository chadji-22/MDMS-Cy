# C5 - Concurrency Testing Evidence

Date: 26/11/2026
Server: Microsoft SQL Server 2025
Database: egeorg28
Tool: SQL Server Management Studio

Two independent sessions:
- Session A: 51
- Session B: 52

## C5.1 - Concurrent bill payments

Result: PASS

Bill ID: 9
Consumer ID: 14
Amount: EUR 19.33

Session A successfully paid the bill.
Session B waited 12 seconds and was rejected
with error 50003 after session A committed.

Final verification:
- Status: PAID
- Completed payments: 1
- Total paid: EUR 19.33

Evidence:
- C5_1_A_Payment.png
- C5_1_A_Commit.png
- C5_1_B_Rejected.png
- C5_1_Final_Verification.png

## C5.2 - Concurrent VEE execution

Result: PASS

Meter ID: 1
Officer ID: 2
Timestamp: 2025-06-17 10:00:00

Session A acquired the exclusive application lock VEE_1.
Session B timed out after 10 seconds.

Session B:
- Meters processed: 0
- Meters failed: 1
- Valid readings: 0

Session A:
- Meters processed: 1
- Meters failed: 0
- Valid readings: 1

Final reading: OBIS 32.7.0, VALID, AUTO.

Evidence:
- C5_2_A_Lock_Acquired.png
- C5_2_B_Lock_Timeout.png
- C5_2_Final_Verification.png

## C5.3 - Concurrent work order assignment

Result: PASS

Work order ID: 13
Officer 1: 2
Officer 2: 3
Technician: 9

Session A proposed 13:00-13:30.
Session B proposed 14:00-14:30.

Session B waited 13 seconds and was rejected
with error 50003 after session A committed.

Final verification:
- Status: ASSIGNED
- Technician ID: 9
- Start: 2026-12-01 13:00:00
- End: 2026-12-01 13:30:00

The first assignment was preserved.

Evidence:
- C5_3_A_Commit.png
- C5_3_B_Rejected.png
- C5_3_Final_Verification.png

The initial successful assignment is confirmed by
the final database verification.

## Conclusion

All three concurrency scenarios passed.
Duplicate payments, overlapping VEE execution and
conflicting work order assignments were prevented.

Tests followed C5_SSMS_demo.md.
No schema or stored procedure changes were required.
