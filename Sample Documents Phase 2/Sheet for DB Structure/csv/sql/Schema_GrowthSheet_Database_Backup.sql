-- =============================================================================
-- Growth Sheet / Education Management - SQL Server Database Schema
-- Prerequisites: States, Districts, Campuses, Quarters, Academic Years, Users
-- Rule 1: Growth sheet uploads per quarter, parsed into Students, Teachers, Growth records
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. LOOKUP / REFERENCE TABLES
-- -----------------------------------------------------------------------------

-- USA States (Admin creates)
CREATE TABLE dbo.States (
    StateId        INT IDENTITY(1,1) NOT NULL,
    StateCode      NVARCHAR(2) NOT NULL,   -- e.g. TX, CA
    StateName      NVARCHAR(100) NOT NULL,
    IsActive       BIT NOT NULL DEFAULT 1,
    CreatedAt      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy      INT NULL,
    CONSTRAINT PK_States PRIMARY KEY (StateId)
);

-- Districts (Admin creates against State)
CREATE TABLE dbo.Districts (
    DistrictId     INT IDENTITY(1,1) NOT NULL,
    StateId        INT NOT NULL,
    DistrictCode   NVARCHAR(50) NULL,
    DistrictName   NVARCHAR(200) NOT NULL,
    IsActive       BIT NOT NULL DEFAULT 1,
    CreatedAt      DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy      INT NULL,
    CONSTRAINT PK_Districts PRIMARY KEY (DistrictId),
    CONSTRAINT FK_Districts_State FOREIGN KEY (StateId) REFERENCES dbo.States(StateId)
);

-- Campus categories (Elementary School, High School, etc.)
CREATE TABLE dbo.CampusCategories (
    CampusCategoryId   INT IDENTITY(1,1) NOT NULL,
    CategoryName       NVARCHAR(100) NOT NULL,  -- Elementary School, High School, etc.
    CategoryCode       NVARCHAR(10) NULL,       -- Optional code
    CONSTRAINT PK_CampusCategories PRIMARY KEY (CampusCategoryId)
);

-- Campuses (Admin creates against District; category, code RE/ME, optional Campus ID)
CREATE TABLE dbo.Campuses (
    CampusId           INT IDENTITY(1,1) NOT NULL,
    DistrictId         INT NOT NULL,
    CampusCategoryId   INT NOT NULL,
    CampusCode         NVARCHAR(20) NOT NULL,   -- RE, ME, etc.
    CampusIdExternal   NVARCHAR(50) NULL,       -- Admin-input Campus ID (from district system)
    CampusName         NVARCHAR(200) NOT NULL,
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy          INT NULL,
    CONSTRAINT PK_Campuses PRIMARY KEY (CampusId),
    CONSTRAINT FK_Campuses_District FOREIGN KEY (DistrictId) REFERENCES dbo.Districts(DistrictId),
    CONSTRAINT FK_Campuses_Category FOREIGN KEY (CampusCategoryId) REFERENCES dbo.CampusCategories(CampusCategoryId)
);

-- Quarter definitions per District (e.g. BOY, PA1, PA2, MOY, PA3, PA4, PA5, EOY)
-- StartDate/EndDate define the quarter window (use year 1900 for month/day template; year is applied from academic year for "current quarter" logic).
CREATE TABLE dbo.DistrictQuarters (
    DistrictQuarterId  INT IDENTITY(1,1) NOT NULL,
    DistrictId         INT NOT NULL,
    QuarterCode        NVARCHAR(20) NOT NULL,  -- BOY, PA1, PA2, MOY, PA3, PA4, PA5, EOY (shown on frontend)
    QuarterName        NVARCHAR(100) NULL,     -- Optional long name, e.g. Beginning of Year, Progress Assessment 1
    StartDate          DATE NOT NULL,          -- Quarter start (e.g. 1900-08-01 = Aug 1; month/day used with academic year)
    EndDate            DATE NOT NULL,           -- Quarter end (e.g. 1900-10-15 = Oct 15)
    SortOrder          TINYINT NOT NULL DEFAULT 1,
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy          INT NULL,
    CONSTRAINT PK_DistrictQuarters PRIMARY KEY (DistrictQuarterId),
    CONSTRAINT FK_DistrictQuarters_District FOREIGN KEY (DistrictId) REFERENCES dbo.Districts(DistrictId),
    CONSTRAINT CK_DistrictQuarters_EndDate CHECK (EndDate >= StartDate)
);

-- -----------------------------------------------------------------------------
-- How the system knows "which quarter we're in" (current quarter from date)
-- -----------------------------------------------------------------------------
-- Academic year is defined by StartDate and EndDate (e.g. 2024-08-01 to 2025-07-31).
-- For "current quarter" logic, use YEAR(StartDate) and YEAR(EndDate) from AcademicYears when resolving quarter start into the academic year.
-- For a given DistrictId, AcademicYearId, and a date (e.g. today):
--   1. Get district quarters ordered by SortOrder.
--   2. For each quarter, resolve StartDate to a date in that academic year (use MONTH/DAY of quarter StartDate; year = YEAR(ay.StartDate) if MONTH >= 8 else YEAR(ay.EndDate)).
--   3. Current quarter = the quarter whose resolved start date is <= today and is the latest such.
-- Frontend: display QuarterCode (BOY, PA1, MOY, EOY, etc.) as the quarter label.

-- Academic year sets (2024-2025, 2025-2026, etc.)
CREATE TABLE dbo.AcademicYears (
    AcademicYearId     INT IDENTITY(1,1) NOT NULL,
    YearLabel          NVARCHAR(20) NOT NULL,  -- 2024-2025, 2025-2026
    StartDate          DATE NOT NULL,          -- e.g. 2024-08-01 (first day of academic year)
    EndDate            DATE NOT NULL,          -- e.g. 2025-07-31 (last day of academic year)
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy          INT NULL,
    CONSTRAINT PK_AcademicYears PRIMARY KEY (AcademicYearId),
    CONSTRAINT UQ_AcademicYears_Label UNIQUE (YearLabel),
    CONSTRAINT CK_AcademicYears_EndDate CHECK (EndDate > StartDate)
);

-- Subjects (RLA, Math, Science, etc.) - can be seeded
CREATE TABLE dbo.Subjects (
    SubjectId      INT IDENTITY(1,1) NOT NULL,
    SubjectCode    NVARCHAR(20) NOT NULL,
    SubjectName    NVARCHAR(100) NOT NULL,
    IsActive       BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Subjects PRIMARY KEY (SubjectId),
    CONSTRAINT UQ_Subjects_Code UNIQUE (SubjectCode)
);

-- Grades (K, 1, 2, ... 12) - shared; campus association via CampusGrades if needed
CREATE TABLE dbo.Grades (
    GradeId        INT IDENTITY(1,1) NOT NULL,
    GradeCode      NVARCHAR(10) NOT NULL,  -- K, 1, 2, ..., 12
    GradeName      NVARCHAR(50) NULL,
    SortOrder      TINYINT NOT NULL DEFAULT 0,
    IsActive       BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_Grades PRIMARY KEY (GradeId),
    CONSTRAINT UQ_Grades_Code UNIQUE (GradeCode)
);

-- Grades offered at a campus (optional: if only some grades per campus)
CREATE TABLE dbo.CampusGrades (
    CampusGradeId  INT IDENTITY(1,1) NOT NULL,
    CampusId       INT NOT NULL,
    GradeId        INT NOT NULL,
    IsActive       BIT NOT NULL DEFAULT 1,
    CONSTRAINT PK_CampusGrades PRIMARY KEY (CampusGradeId),
    CONSTRAINT FK_CampusGrades_Campus FOREIGN KEY (CampusId) REFERENCES dbo.Campuses(CampusId),
    CONSTRAINT FK_CampusGrades_Grade FOREIGN KEY (GradeId) REFERENCES dbo.Grades(GradeId),
    CONSTRAINT UQ_CampusGrades UNIQUE (CampusId, GradeId)
);

-- -----------------------------------------------------------------------------
-- 2. USERS & ROLES
-- -----------------------------------------------------------------------------

CREATE TABLE dbo.Roles (
    RoleId         INT IDENTITY(1,1) NOT NULL,
    RoleName       NVARCHAR(50) NOT NULL,  -- SuperAdmin, DistrictAdmin, Principal, Teacher
    Description    NVARCHAR(200) NULL,
    CONSTRAINT PK_Roles PRIMARY KEY (RoleId),
    CONSTRAINT UQ_Roles_Name UNIQUE (RoleName)
);

CREATE TABLE dbo.Users (
    UserId             INT IDENTITY(1,1) NOT NULL,
    RoleId             INT NOT NULL,
    Email              NVARCHAR(256) NOT NULL,
    DisplayName        NVARCHAR(200) NULL,
    -- Scope: SuperAdmin = nulls; DistrictAdmin = DistrictId; Principal = CampusId; Teacher = link via TeacherId
    DistrictId         INT NOT NULL,
    CampusId           INT NULL,
    TeacherId          INT NULL,          -- FK added after Teachers table
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CreatedBy          INT NULL,
    CONSTRAINT PK_Users PRIMARY KEY (UserId),
    CONSTRAINT FK_Users_Role FOREIGN KEY (RoleId) REFERENCES dbo.Roles(RoleId),
    CONSTRAINT FK_Users_District FOREIGN KEY (DistrictId) REFERENCES dbo.Districts(DistrictId),
    CONSTRAINT FK_Users_Campus FOREIGN KEY (CampusId) REFERENCES dbo.Campuses(CampusId),
    CONSTRAINT UQ_Users_Email UNIQUE (Email)
);

-- -----------------------------------------------------------------------------
-- 3. TEACHERS & STUDENTS
-- -----------------------------------------------------------------------------

-- Teachers (from growth sheet + admin; same teacher can teach multiple grades/subjects at same campus)
CREATE TABLE dbo.Teachers (
    TeacherId          INT IDENTITY(1,1) NOT NULL,
    TeacherIdExternal  NVARCHAR(50) NOT NULL,   -- E19189, E15819 (from sheet)
    FirstName          NVARCHAR(100) NOT NULL,
    LastName           NVARCHAR(100) NOT NULL,
    DisplayName        AS (LastName + N', ' + FirstName) PERSISTED,
    IsActive           BIT NOT NULL DEFAULT 1,
    CreatedAt          DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt          DATETIME2 NULL,
    CONSTRAINT PK_Teachers PRIMARY KEY (TeacherId),
    CONSTRAINT UQ_Teachers_External UNIQUE (TeacherIdExternal)
);

-- Link User (Principal/Teacher) to Teacher
ALTER TABLE dbo.Users ADD CONSTRAINT FK_Users_Teacher FOREIGN KEY (TeacherId) REFERENCES dbo.Teachers(TeacherId);

-- Teacher assignment to Campus + Grade + Subject (same teacher, multiple grades/subjects at same campus)
CREATE TABLE dbo.TeacherCampusAssignments (
    TeacherCampusAssignmentId   INT IDENTITY(1,1) NOT NULL,
    TeacherId                  INT NOT NULL,
    CampusId                   INT NOT NULL,
    GradeId                    INT NOT NULL,
    SubjectId                  INT NOT NULL,
    AcademicYearId             INT NOT NULL,
    IsActive                   BIT NOT NULL DEFAULT 1,
    CreatedAt                  DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_TeacherCampusAssignments PRIMARY KEY (TeacherCampusAssignmentId),
    CONSTRAINT FK_TCA_Teacher FOREIGN KEY (TeacherId) REFERENCES dbo.Teachers(TeacherId),
    CONSTRAINT FK_TCA_Campus FOREIGN KEY (CampusId) REFERENCES dbo.Campuses(CampusId),
    CONSTRAINT FK_TCA_Grade FOREIGN KEY (GradeId) REFERENCES dbo.Grades(GradeId),
    CONSTRAINT FK_TCA_Subject FOREIGN KEY (SubjectId) REFERENCES dbo.Subjects(SubjectId),
    CONSTRAINT FK_TCA_AcademicYear FOREIGN KEY (AcademicYearId) REFERENCES dbo.AcademicYears(AcademicYearId),
    CONSTRAINT UQ_TCA UNIQUE (TeacherId, CampusId, GradeId, SubjectId, AcademicYearId)
);

-- Students (from growth sheet + admin)
CREATE TABLE dbo.Students (
    StudentId         INT IDENTITY(1,1) NOT NULL,
    LocalId           NVARCHAR(50) NOT NULL,   -- District/sheet Local ID (85060, 85230, etc.)
    FirstName         NVARCHAR(100) NOT NULL,
    LastName          NVARCHAR(100) NOT NULL,
    DisplayName       AS (LastName + N', ' + FirstName) PERSISTED,
    CampusId          INT NOT NULL,           -- Current campus
    GradeId           INT NOT NULL,
    -- Demographics (from sheet, can be updated over time)
    SpecialEdIndicator     BIT NULL,
    EconomicDisadvantage   BIT NULL,
    EmergentBilingual     NVARCHAR(100) NULL,
    Ethnicity             NVARCHAR(100) NULL,
    TestLang              NVARCHAR(50) NULL,
    IsActive          BIT NOT NULL DEFAULT 1,
    CreatedAt         DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UpdatedAt         DATETIME2 NULL,
    CONSTRAINT PK_Students PRIMARY KEY (StudentId),
    CONSTRAINT FK_Students_Campus FOREIGN KEY (CampusId) REFERENCES dbo.Campuses(CampusId),
    CONSTRAINT FK_Students_Grade FOREIGN KEY (GradeId) REFERENCES dbo.Grades(GradeId)
);

-- Unique student per campus (same LocalId could exist in different districts/campuses)
CREATE UNIQUE INDEX UQ_Students_Campus_LocalId ON dbo.Students (CampusId, LocalId);

-- -----------------------------------------------------------------------------
-- 4. GROWTH SHEET UPLOAD & STUDENT GROWTH RECORDS
-- -----------------------------------------------------------------------------

-- One row per uploaded growth sheet (quarter + academic year + district/campus)
CREATE TABLE dbo.GrowthSheetUploads (
    GrowthSheetUploadId   INT IDENTITY(1,1) NOT NULL,
    DistrictId            INT NOT NULL,
    CampusId              INT NOT NULL,
    AcademicYearId        INT NOT NULL,
    DistrictQuarterId     INT NOT NULL,
    FileName              NVARCHAR(500) NULL,
    UploadedAt            DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    UploadedBy            INT NULL,
    RowCount              INT NULL,
    Status                NVARCHAR(20) NOT NULL DEFAULT N'Completed', -- Completed, Failed, Partial
    ErrorMessage          NVARCHAR(MAX) NULL,
    CONSTRAINT PK_GrowthSheetUploads PRIMARY KEY (GrowthSheetUploadId),
    CONSTRAINT FK_GSU_District FOREIGN KEY (DistrictId) REFERENCES dbo.Districts(DistrictId),
    CONSTRAINT FK_GSU_Campus FOREIGN KEY (CampusId) REFERENCES dbo.Campuses(CampusId),
    CONSTRAINT FK_GSU_AcademicYear FOREIGN KEY (AcademicYearId) REFERENCES dbo.AcademicYears(AcademicYearId),
    CONSTRAINT FK_GSU_DistrictQuarter FOREIGN KEY (DistrictQuarterId) REFERENCES dbo.DistrictQuarters(DistrictQuarterId),
    CONSTRAINT FK_GSU_UploadedBy FOREIGN KEY (UploadedBy) REFERENCES dbo.Users(UserId)
);

-- Student growth-specific record per quarter (one row per student per subject per quarter per year)
CREATE TABLE dbo.StudentGrowthRecords (
    StudentGrowthRecordId   INT IDENTITY(1,1) NOT NULL,
    GrowthSheetUploadId     INT NOT NULL,
    StudentId               INT NOT NULL,
    SubjectId               INT NOT NULL,
    TeacherId               INT NULL,
    -- Assessment / growth metrics (from sheet)
    STAAR                   NVARCHAR(50) NULL,       -- 55%, etc.
    STAARPerLevel           TINYINT NULL,
    QuarterScore            NVARCHAR(50) NULL,       -- Q3 value
    QuarterPerLevel         TINYINT NULL,
    Delta                   INT NULL,
    Growth                  DECIMAL(10,4) NULL,
    HB1416                  DECIMAL(10,4) NULL,
    HB1416Delta             DECIMAL(10,4) NULL,
    TotalGrowthForQuarter   DECIMAL(10,4) NULL,
    App                     TINYINT NULL,
    Meets                   TINYINT NULL,
    Masters                 TINYINT NULL,
    CS                      NVARCHAR(50) NULL,       -- e.g. 67%
    CreatedAt               DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_StudentGrowthRecords PRIMARY KEY (StudentGrowthRecordId),
    CONSTRAINT FK_SGR_Upload FOREIGN KEY (GrowthSheetUploadId) REFERENCES dbo.GrowthSheetUploads(GrowthSheetUploadId),
    CONSTRAINT FK_SGR_Student FOREIGN KEY (StudentId) REFERENCES dbo.Students(StudentId),
    CONSTRAINT FK_SGR_Subject FOREIGN KEY (SubjectId) REFERENCES dbo.Subjects(SubjectId),
    CONSTRAINT FK_SGR_Teacher FOREIGN KEY (TeacherId) REFERENCES dbo.Teachers(TeacherId)
);

-- One growth record per student per subject per quarter per upload (one sheet = one quarter per campus/year)
CREATE UNIQUE INDEX UQ_StudentGrowthRecords ON dbo.StudentGrowthRecords (GrowthSheetUploadId, StudentId, SubjectId);

-- -----------------------------------------------------------------------------
-- 5. INDEXES FOR QUERYING BY ACADEMIC YEAR, QUARTER, CAMPUS
-- -----------------------------------------------------------------------------

CREATE INDEX IX_GrowthSheetUploads_AcademicYear ON dbo.GrowthSheetUploads (AcademicYearId);
CREATE INDEX IX_GrowthSheetUploads_Campus ON dbo.GrowthSheetUploads (CampusId);
CREATE INDEX IX_GrowthSheetUploads_Quarter ON dbo.GrowthSheetUploads (DistrictQuarterId);
CREATE INDEX IX_StudentGrowthRecords_Student ON dbo.StudentGrowthRecords (StudentId);
CREATE INDEX IX_StudentGrowthRecords_Teacher ON dbo.StudentGrowthRecords (TeacherId);
CREATE INDEX IX_Students_Campus ON dbo.Students (CampusId);
CREATE INDEX IX_Students_LocalId ON dbo.Students (LocalId);

-- -----------------------------------------------------------------------------
-- 6. SEED ROLES (optional)
-- -----------------------------------------------------------------------------

INSERT INTO dbo.Roles (RoleName, Description) VALUES
    (N'SuperAdmin', N'Full system access'),
    (N'DistrictAdmin', N'District-level admin'),
    (N'Principal', N'Principal (campus-level admin)'),
    (N'Teacher', N'Teacher access');

-- -----------------------------------------------------------------------------
-- 7. GET CURRENT QUARTER (example: how system knows quarter from date)
-- -----------------------------------------------------------------------------
-- Returns the DistrictQuarterId for the quarter that contains @AsOfDate
-- for the given district and academic year. Use QuarterCode (BOY, PA1, MOY, etc.) on frontend.
/*
CREATE FUNCTION dbo.fn_GetCurrentDistrictQuarterId (
    @DistrictId     INT,
    @AcademicYearId INT,
    @AsOfDate       DATE  -- e.g. CAST(GETUTCDATE() AS DATE)
)
RETURNS INT
AS
BEGIN
    DECLARE @StartYear SMALLINT, @EndYear SMALLINT;
    SELECT @StartYear = YEAR(StartDate), @EndYear = YEAR(EndDate)
    FROM dbo.AcademicYears WHERE AcademicYearId = @AcademicYearId;

    RETURN (
        SELECT TOP (1) dq.DistrictQuarterId
        FROM dbo.DistrictQuarters dq
        WHERE dq.DistrictId = @DistrictId
          AND dq.IsActive = 1
          AND (
              (MONTH(dq.StartDate) >= 8 AND DATEFROMPARTS(@StartYear, MONTH(dq.StartDate), DAY(dq.StartDate)) <= @AsOfDate)
              OR
              (MONTH(dq.StartDate) < 8 AND DATEFROMPARTS(@EndYear, MONTH(dq.StartDate), DAY(dq.StartDate)) <= @AsOfDate)
          )
        ORDER BY
          CASE WHEN MONTH(dq.StartDate) >= 8
               THEN DATEFROMPARTS(@StartYear, MONTH(dq.StartDate), DAY(dq.StartDate))
               ELSE DATEFROMPARTS(@EndYear, MONTH(dq.StartDate), DAY(dq.StartDate))
          END DESC
    );
END;
*/
-- Usage: SELECT dbo.fn_GetCurrentDistrictQuarterId(1, 1, CAST(GETUTCDATE() AS DATE));

-- -----------------------------------------------------------------------------
-- SUMMARY
-- -----------------------------------------------------------------------------
-- States          -> Districts -> Campuses (with CampusCategories, CampusCode, CampusIdExternal)
-- Districts       -> DistrictQuarters (quarter definitions per district)
-- AcademicYears   -> used by GrowthSheetUploads, TeacherCampusAssignments
-- GrowthSheetUploads: one per quarter per campus per academic year (upload metadata)
-- Students        -> Campus, Grade; identified by LocalId per Campus
-- Teachers        -> TeacherCampusAssignments (Campus + Grade + Subject + AcademicYear)
-- StudentGrowthRecords: growth metrics per Student, Subject, Quarter (via GrowthSheetUploadId), with TeacherId
-- Users           -> Roles; optional DistrictId, CampusId, TeacherId for scope
