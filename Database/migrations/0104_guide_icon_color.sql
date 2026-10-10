-- Study guides: each guide picks its own card icon and colour in
-- Admin → Website → Study Guides (used when the guide has no cover photo).
-- Before this the site picked them by position, so a new guide had no say.
-- Existing guides are backfilled with the icons/colours they showed before.
-- Also adds the "Cost of studying in China" guide (English; other languages
-- fall back to English until translated in the admin).
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF COL_LENGTH('syst.Guide', 'Icon') IS NULL
    ALTER TABLE syst.Guide ADD [Icon] VARCHAR(40) NOT NULL CONSTRAINT DF_syst_Guide_Icon DEFAULT ('')
GO
IF COL_LENGTH('syst.Guide', 'Color') IS NULL
    ALTER TABLE syst.Guide ADD [Color] VARCHAR(20) NOT NULL CONSTRAINT DF_syst_Guide_Color DEFAULT ('')
GO

;WITH o AS (SELECT GuideID, Icon, Color, ROW_NUMBER() OVER (ORDER BY SortOrder, GuideID) - 1 AS N FROM syst.Guide)
UPDATE o SET
    Icon  = CHOOSE(N % 6 + 1, 'graduation-cap', 'book-open', 'plane', 'award', 'stethoscope', 'languages'),
    Color = CHOOSE(N % 6 + 1, 'navy', 'blue', 'purple', 'teal', 'green', 'amber')
WHERE Icon = ''
GO

IF OBJECT_ID('syst.Guide_List') IS NOT NULL DROP PROCEDURE syst.Guide_List
GO
CREATE PROCEDURE [syst].[Guide_List] (@APIKey VARCHAR(100), @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT GuideID, Slug, CoverImageURL, Icon, Color, ContentJSON, SortOrder, IsActive, PublishedDate, UpdatedDate
        FROM syst.Guide
        WHERE (@PublicOnly = 0 OR IsActive = 'A')
        ORDER BY SortOrder, GuideID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_List', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Guide_Get') IS NOT NULL DROP PROCEDURE syst.Guide_Get
GO
CREATE PROCEDURE [syst].[Guide_Get] (@APIKey VARCHAR(100), @GuideID INT = 0, @Slug VARCHAR(150) = '', @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT GuideID, Slug, CoverImageURL, Icon, Color, ContentJSON, SortOrder, IsActive, PublishedDate, UpdatedDate
        FROM syst.Guide
        WHERE (GuideID = @GuideID OR (ISNULL(@Slug, '') <> '' AND Slug = @Slug))
          AND (@PublicOnly = 0 OR IsActive = 'A')
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_Get', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Guide_AddEdit') IS NOT NULL DROP PROCEDURE syst.Guide_AddEdit
GO
CREATE PROCEDURE [syst].[Guide_AddEdit] (
    @APIKey VARCHAR(100), @GuideID INT, @Slug VARCHAR(150), @CoverImageURL NVARCHAR(500),
    @ContentJSON NVARCHAR(MAX), @IsActive CHAR(1) = 'A', @Icon VARCHAR(40) = '', @Color VARCHAR(20) = '')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF EXISTS (SELECT 1 FROM syst.Guide WHERE Slug = @Slug AND GuideID <> ISNULL(@GuideID, 0))
            THROW 50001, 'Another guide already uses this web address.', 1;

        IF ISNULL(@GuideID, 0) = 0
            INSERT INTO syst.Guide (Slug, CoverImageURL, Icon, Color, ContentJSON, SortOrder, IsActive)
            VALUES (@Slug, ISNULL(@CoverImageURL, ''), ISNULL(@Icon, ''), ISNULL(@Color, ''), @ContentJSON,
                    ISNULL((SELECT MAX(SortOrder) FROM syst.Guide), 0) + 1, ISNULL(@IsActive, 'A'))
        ELSE
            UPDATE syst.Guide
            SET Slug = @Slug, CoverImageURL = ISNULL(@CoverImageURL, ''), Icon = ISNULL(@Icon, ''), Color = ISNULL(@Color, ''),
                ContentJSON = @ContentJSON, IsActive = ISNULL(@IsActive, 'A'), UpdatedDate = GETDATE()
            WHERE GuideID = @GuideID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF NOT EXISTS (SELECT 1 FROM syst.Guide WHERE Slug = 'cost-of-studying-in-china-for-sri-lankans')
INSERT INTO syst.Guide (Slug, CoverImageURL, Icon, Color, ContentJSON, SortOrder, IsActive)
VALUES ('cost-of-studying-in-china-for-sri-lankans', '', 'wallet', 'rose', N'{"en":{"title":"Cost of Studying in China for Sri Lankan Students: Fees & Living Costs","seoTitle":"Cost of Studying in China from Sri Lanka — Fees & Living Costs | Proton Education","description":"How much it costs a Sri Lankan student to study in China: tuition fees, hostel and living costs, one-time costs like the visa and medical check, and how scholarships and budgeting can bring the total down.","bodyHtml":"<p>Cost is usually the first question Sri Lankan families ask about studying in China. The good news: tuition and living costs in China are generally lower than in the UK, Australia or the USA, and scholarships can reduce them further. This guide breaks down where the money goes so you can plan a realistic budget.</p><p><em>The figures below are typical ranges to help you plan. Every university sets its own fees and they change each year, so always check the exact amounts for your chosen program — Proton Education Services can confirm them for you.</em></p><h2>1. Tuition fees</h2><p>Tuition depends on the university, the city and the subject:</p><ul><li><strong>Chinese language / foundation programs:</strong> often the most affordable option.</li><li><strong>Bachelor''s degrees (English-taught):</strong> usually a moderate yearly fee; engineering, business and IT programs vary by university ranking.</li><li><strong>Medicine (MBBS):</strong> normally higher than other bachelor''s programs and runs for six years including internship.</li><li><strong>Master''s and PhD:</strong> fees vary widely, and research degrees are the most likely to be covered by scholarships.</li></ul><p>Universities in big cities such as Beijing and Shanghai tend to charge more than equally good universities in other provinces.</p><h2>2. Accommodation</h2><p>Most international students live in the university''s international student dormitory for their first year. It is usually the cheapest and safest choice — shared rooms cost less than single rooms. Renting a private apartment off campus costs more and often needs a deposit and registration with the local police.</p><h2>3. Living costs</h2><ul><li><strong>Food:</strong> campus canteens are very affordable; eating out and imported food cost more.</li><li><strong>Transport:</strong> metro and buses are cheap, and student discounts are common.</li><li><strong>Phone and internet:</strong> a local SIM with a data plan is inexpensive.</li><li><strong>Books and personal expenses:</strong> plan a small monthly amount.</li></ul><p>Living costs in smaller cities can be noticeably lower than in Beijing, Shanghai or Shenzhen.</p><h2>4. One-time costs before and after you arrive</h2><ul><li>Application fees charged by some universities</li><li>Passport, document translation and attestation</li><li>The X1 or X2 student visa fee (see our <a href=\"/guides/china-student-visa-sri-lanka\">China student visa guide</a>)</li><li>Medical examination (the Foreigner Physical Examination Form)</li><li>Flight from Colombo to China</li><li>Compulsory student health insurance in China</li><li>Residence permit fee after arrival (for X1 visa holders)</li></ul><h2>5. How to bring the cost down</h2><ul><li><strong>Apply for scholarships</strong> — the Chinese Government (CSC) Scholarship and university scholarships can cover tuition, accommodation and even a monthly stipend. Read our <a href=\"/guides/chinese-government-scholarship-sri-lanka\">CSC scholarship guide</a>.</li><li><strong>Choose the city wisely</strong> — a well-ranked university outside the biggest cities can save a lot.</li><li><strong>Stay in the campus dormitory</strong>, at least for the first year.</li><li><strong>Learn some Chinese</strong> — it makes daily life cheaper and opens up part-time internships allowed for students.</li></ul><p><strong>Note on working:</strong> international students in China may only do part-time work or internships with permission from their university and the immigration authorities. Do not plan your budget around part-time income.</p><h2>6. Sample budget checklist</h2><ol><li>Yearly tuition fee (from the admission letter)</li><li>Yearly accommodation fee</li><li>Monthly living costs × 12</li><li>Insurance</li><li>One-time costs for the first year (visa, medical, flights, residence permit)</li><li>An emergency reserve</li></ol><p>Add these up for every year of your program and compare universities side by side before you decide.</p><h2>How Proton Education Services helps</h2><p>We help Sri Lankan students compare universities by total cost, apply for scholarships, and prepare visa and admission documents — so there are no surprises after you arrive. <a href=\"/contact\">Contact us</a> for free advice on a budget that fits your family.</p>","faq":[{"q":"Is studying in China cheaper than the UK or Australia?","a":"Generally yes. Tuition and living costs in China are usually lower than in the UK, Australia or the USA, and scholarships can reduce the cost further. Exact fees depend on the university and program."},{"q":"Can I get a full scholarship to study in China?","a":"Yes. The Chinese Government (CSC) Scholarship and some university scholarships can cover tuition, accommodation, insurance and a monthly stipend. Competition is strong, so apply early with good results and documents."},{"q":"Can I work part-time while studying in China?","a":"Only with permission from your university and the immigration authorities, and usually only limited part-time work or internships. You should not rely on part-time income to pay your fees."},{"q":"Which costs do I pay before leaving Sri Lanka?","a":"Typically application fees, document translation and attestation, the medical examination, the student visa fee, your flight, and often the first payment of tuition and accommodation."}]}}',
        ISNULL((SELECT MAX(SortOrder) FROM syst.Guide), 0) + 1, 'A')
GO
