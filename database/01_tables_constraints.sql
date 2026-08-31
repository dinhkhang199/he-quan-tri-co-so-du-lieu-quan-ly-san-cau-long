/* ============================================================
   BadmintonCourtManagement
   Script : 01_tables_constraints.sql
   Mục đích: Tạo 5 bảng lõi + PK/FK/UNIQUE/CHECK theo contract v2.0
   Bảng   : Users, Courts, Bookings, ActivityLogs, Notifications
   ============================================================ */

USE BadmintonCourtManagement;
GO

-- ------------------------------------------------------------
-- Bảng 1: Users
-- ------------------------------------------------------------
IF OBJECT_ID(N'dbo.ActivityLogs', N'U') IS NOT NULL DROP TABLE dbo.ActivityLogs;
IF OBJECT_ID(N'dbo.Notifications', N'U') IS NOT NULL DROP TABLE dbo.Notifications;
IF OBJECT_ID(N'dbo.Bookings', N'U') IS NOT NULL DROP TABLE dbo.Bookings;
IF OBJECT_ID(N'dbo.Courts', N'U') IS NOT NULL DROP TABLE dbo.Courts;
IF OBJECT_ID(N'dbo.Users', N'U') IS NOT NULL DROP TABLE dbo.Users;
GO

CREATE TABLE dbo.Users
(
    UserId       UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Users_UserId DEFAULT NEWID(),
    Username     NVARCHAR(50)     NOT NULL,
    PasswordHash VARBINARY(64)    NOT NULL,          -- SHA2_256 với prefix namespace cố định; không phải per-user salt
    PhoneNumber  NVARCHAR(20)     NOT NULL,
    Role         NVARCHAR(20)     NOT NULL,
    IsActive     BIT              NOT NULL CONSTRAINT DF_Users_IsActive DEFAULT 1,
    LastLogin    DATETIME2(0)     NULL,
    CreatedAt    DATETIME2(0)     NOT NULL CONSTRAINT DF_Users_CreatedAt DEFAULT SYSDATETIME(),
    UpdatedAt    DATETIME2(0)     NOT NULL CONSTRAINT DF_Users_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Users PRIMARY KEY (UserId),
    CONSTRAINT UQ_Users_Username     UNIQUE (Username),
    CONSTRAINT UQ_Users_PhoneNumber  UNIQUE (PhoneNumber),
    -- Role phải thuộc tập giá trị contract (DB-05)
    CONSTRAINT CK_Users_Role CHECK (Role IN (N'GUEST', N'CUSTOMER', N'COURT_MANAGER', N'MANAGER'))
);
GO

-- ------------------------------------------------------------
-- Bảng 2: Courts
-- ------------------------------------------------------------
CREATE TABLE dbo.Courts
(
    CourtId            UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Courts_CourtId DEFAULT NEWID(),
    CourtName          NVARCHAR(100)    NOT NULL,
    Address            NVARCHAR(255)    NOT NULL,
    SurfaceType        NVARCHAR(20)     NOT NULL,   -- STANDARD / VIP
    SizeType           NVARCHAR(20)     NOT NULL,   -- SINGLE / DOUBLE
    PricePerHour       DECIMAL(12,0)    NOT NULL,
    PricePerThreeHours DECIMAL(12,0)    NOT NULL,
    ImageUrl           NVARCHAR(500)    NULL,
    OwnerId            UNIQUEIDENTIFIER NOT NULL,
    IsActive           BIT              NOT NULL CONSTRAINT DF_Courts_IsActive DEFAULT 1,
    CreatedAt          DATETIME2(0)     NOT NULL CONSTRAINT DF_Courts_CreatedAt DEFAULT SYSDATETIME(),
    UpdatedAt          DATETIME2(0)     NOT NULL CONSTRAINT DF_Courts_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Courts PRIMARY KEY (CourtId),
    CONSTRAINT FK_Courts_Owner_Users FOREIGN KEY (OwnerId) REFERENCES dbo.Users(UserId),
    -- Giá luôn > 0 (DB-03)
    CONSTRAINT CK_Courts_PricePerHour_GT0       CHECK (PricePerHour       > 0),
    CONSTRAINT CK_Courts_PricePerThreeHours_GT0 CHECK (PricePerThreeHours > 0),
    -- Bộ giá trị theo contract (DB-05)
    CONSTRAINT CK_Courts_SurfaceType CHECK (SurfaceType IN (N'STANDARD', N'VIP')),
    CONSTRAINT CK_Courts_SizeType    CHECK (SizeType    IN (N'SINGLE', N'DOUBLE'))
);
GO

-- ------------------------------------------------------------
-- Bảng 3: Bookings
-- ------------------------------------------------------------
CREATE TABLE dbo.Bookings
(
    BookingId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Bookings_BookingId DEFAULT NEWID(),
    UserId    UNIQUEIDENTIFIER NOT NULL,
    CourtId   UNIQUEIDENTIFIER NOT NULL,
    StartTime DATETIME2(0)     NOT NULL,
    EndTime   DATETIME2(0)     NOT NULL,
    Status    NVARCHAR(20)     NOT NULL CONSTRAINT DF_Bookings_Status DEFAULT N'PENDING',
    TotalCost DECIMAL(12,0)    NOT NULL CONSTRAINT DF_Bookings_TotalCost DEFAULT 0,
    CreatedAt DATETIME2(0)     NOT NULL CONSTRAINT DF_Bookings_CreatedAt DEFAULT SYSDATETIME(),
    UpdatedAt DATETIME2(0)     NOT NULL CONSTRAINT DF_Bookings_UpdatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Bookings PRIMARY KEY (BookingId),
    CONSTRAINT FK_Bookings_User_Users  FOREIGN KEY (UserId)  REFERENCES dbo.Users(UserId),
    CONSTRAINT FK_Bookings_Court_Courts FOREIGN KEY (CourtId) REFERENCES dbo.Courts(CourtId),
    -- Start < End (DB-04)
    CONSTRAINT CK_Bookings_Start_LT_End CHECK (StartTime < EndTime),
    -- Status thuộc tập giá trị contract (DB-05)
    CONSTRAINT CK_Bookings_Status CHECK (Status IN (N'PENDING', N'BOOKED', N'COMPLETED', N'REJECTED', N'CANCELLED'))
);
GO

-- ------------------------------------------------------------
-- Bảng 4: ActivityLogs (audit)
-- ------------------------------------------------------------
CREATE TABLE dbo.ActivityLogs
(
    LogId     UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_ActivityLogs_LogId DEFAULT NEWID(),
    UserId    UNIQUEIDENTIFIER NOT NULL,
    BookingId UNIQUEIDENTIFIER NULL,
    Action    NVARCHAR(50)     NOT NULL,
    OldStatus NVARCHAR(20)     NULL,
    NewStatus NVARCHAR(20)     NULL,
    CreatedAt DATETIME2(0)     NOT NULL CONSTRAINT DF_ActivityLogs_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_ActivityLogs PRIMARY KEY (LogId),
    CONSTRAINT FK_ActivityLogs_User_Users     FOREIGN KEY (UserId)     REFERENCES dbo.Users(UserId),
    CONSTRAINT FK_ActivityLogs_Booking_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(BookingId)
);
GO

-- ------------------------------------------------------------
-- Bảng 5: Notifications
-- ------------------------------------------------------------
CREATE TABLE dbo.Notifications
(
    NotificationId UNIQUEIDENTIFIER NOT NULL CONSTRAINT DF_Notifications_NotificationId DEFAULT NEWID(),
    UserId         UNIQUEIDENTIFIER NOT NULL,
    BookingId      UNIQUEIDENTIFIER NULL,
    Message        NVARCHAR(500)    NOT NULL,
    IsRead         BIT              NOT NULL CONSTRAINT DF_Notifications_IsRead DEFAULT 0,
    CreatedAt      DATETIME2(0)     NOT NULL CONSTRAINT DF_Notifications_CreatedAt DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Notifications PRIMARY KEY (NotificationId),
    CONSTRAINT FK_Notifications_User_Users     FOREIGN KEY (UserId)     REFERENCES dbo.Users(UserId),
    CONSTRAINT FK_Notifications_Booking_Bookings FOREIGN KEY (BookingId) REFERENCES dbo.Bookings(BookingId)
);
GO

PRINT N'[OK] 5 bảng lõi + constraints đã được tạo.';
