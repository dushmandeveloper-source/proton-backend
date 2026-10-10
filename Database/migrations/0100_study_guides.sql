-- Study guides / blog posts for the public site (Admin → Website → Study
-- Guides). One row per guide; ContentJSON holds the text per language:
--   { "en": { "title", "seoTitle", "description", "bodyHtml", "faq": [{q,a}] },
--     "zh": {...}, "si": {...}, "ta": {...} }
-- A missing language falls back to English on the site. bodyHtml is
-- sanitised by the backend on save (Ganss.Xss HtmlSanitizer).
-- Read publicly via GET /api/guides and /api/guides/{slug}.
--
-- No USE statement -- see Database/tools/apply-migrations.ps1 / ENVIRONMENTS.md.

IF OBJECT_ID('syst.Guide') IS NULL
BEGIN
    CREATE TABLE [syst].[Guide](
        [GuideID]       [int] IDENTITY(1,1) NOT NULL,
        [Slug]          [varchar](150)  NOT NULL,
        [CoverImageURL] [nvarchar](500) NOT NULL DEFAULT (''),
        [ContentJSON]   [nvarchar](max) NOT NULL,
        [SortOrder]     [int]           NOT NULL DEFAULT (0),
        [IsActive]      [char](1)       NOT NULL DEFAULT ('A'),
        [PublishedDate] [datetime]      NOT NULL DEFAULT (GETDATE()),
        [UpdatedDate]   [datetime]      NOT NULL DEFAULT (GETDATE()),
        CONSTRAINT [PK_syst_Guide] PRIMARY KEY CLUSTERED ([GuideID] ASC),
        CONSTRAINT [UQ_syst_Guide_Slug] UNIQUE ([Slug])
    )
END
GO

IF OBJECT_ID('syst.Guide_List') IS NOT NULL DROP PROCEDURE syst.Guide_List
GO
-- @PublicOnly = 1: only active guides (public site).
CREATE PROCEDURE [syst].[Guide_List] (@APIKey VARCHAR(100), @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT GuideID, Slug, CoverImageURL, ContentJSON, SortOrder, IsActive, PublishedDate, UpdatedDate
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
-- By id (admin) or slug (public; @PublicOnly hides inactive guides).
CREATE PROCEDURE [syst].[Guide_Get] (@APIKey VARCHAR(100), @GuideID INT = 0, @Slug VARCHAR(150) = '', @PublicOnly BIT = 0)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        SELECT GuideID, Slug, CoverImageURL, ContentJSON, SortOrder, IsActive, PublishedDate, UpdatedDate
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
-- @GuideID = 0 inserts (appended to the end of the order). Throws on a duplicate slug.
CREATE PROCEDURE [syst].[Guide_AddEdit] (
    @APIKey VARCHAR(100), @GuideID INT, @Slug VARCHAR(150), @CoverImageURL NVARCHAR(500),
    @ContentJSON NVARCHAR(MAX), @IsActive CHAR(1) = 'A')
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        IF EXISTS (SELECT 1 FROM syst.Guide WHERE Slug = @Slug AND GuideID <> ISNULL(@GuideID, 0))
            THROW 50001, 'Another guide already uses this web address.', 1;

        IF ISNULL(@GuideID, 0) = 0
            INSERT INTO syst.Guide (Slug, CoverImageURL, ContentJSON, SortOrder, IsActive)
            VALUES (@Slug, ISNULL(@CoverImageURL, ''), @ContentJSON,
                    ISNULL((SELECT MAX(SortOrder) FROM syst.Guide), 0) + 1, ISNULL(@IsActive, 'A'))
        ELSE
            UPDATE syst.Guide
            SET Slug = @Slug, CoverImageURL = ISNULL(@CoverImageURL, ''), ContentJSON = @ContentJSON,
                IsActive = ISNULL(@IsActive, 'A'), UpdatedDate = GETDATE()
            WHERE GuideID = @GuideID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_AddEdit', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Guide_Delete') IS NOT NULL DROP PROCEDURE syst.Guide_Delete
GO
CREATE PROCEDURE [syst].[Guide_Delete] (@APIKey VARCHAR(100), @GuideID INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        DELETE FROM syst.Guide WHERE GuideID = @GuideID
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_Delete', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

IF OBJECT_ID('syst.Guide_Move') IS NOT NULL DROP PROCEDURE syst.Guide_Move
GO
-- Swap with the neighbour: @Direction -1 = up, 1 = down.
CREATE PROCEDURE [syst].[Guide_Move] (@APIKey VARCHAR(100), @GuideID INT, @Direction INT)
AS
BEGIN
    SET NOCOUNT ON
    BEGIN TRY
        IF NOT EXISTS (SELECT 1 FROM syst.APIKey WHERE KeyValue = @APIKey AND ActiveStatus = 'A') BEGIN ;THROW 50000, 'Invalid API Key', 1; END
        ;WITH O AS (SELECT GuideID, ROW_NUMBER() OVER (ORDER BY SortOrder, GuideID) AS RN FROM syst.Guide)
        UPDATE G SET SortOrder = O.RN FROM syst.Guide G JOIN O ON O.GuideID = G.GuideID

        DECLARE @Cur INT = (SELECT SortOrder FROM syst.Guide WHERE GuideID = @GuideID)
        DECLARE @OtherID INT = (SELECT GuideID FROM syst.Guide WHERE SortOrder = @Cur + SIGN(@Direction))
        IF @OtherID IS NOT NULL
        BEGIN
            UPDATE syst.Guide SET SortOrder = @Cur WHERE GuideID = @OtherID
            UPDATE syst.Guide SET SortOrder = @Cur + SIGN(@Direction) WHERE GuideID = @GuideID
        END
    END TRY
    BEGIN CATCH
        DECLARE @ERROR_MESSAGE VARCHAR(4000) = ERROR_MESSAGE(); RAISERROR('%s. Script: syst.Guide_Move', 16, 1, @ERROR_MESSAGE);
    END CATCH
END
GO

-- Seed: the 6 guides already on the website (English).
IF NOT EXISTS (SELECT 1 FROM syst.Guide)
BEGIN
    INSERT INTO syst.Guide (Slug, SortOrder, ContentJSON) VALUES
    (N'study-in-china-from-sri-lanka', 1, N'{"en":{"title":"Study in China from Sri Lanka: The Complete Guide","seoTitle":"Study in China from Sri Lanka — Complete Guide | Proton Education","description":"Everything Sri Lankan students need to know about Sri Lanka to China education: programs, entry requirements, costs, scholarships, the X1 student visa and how Proton Education Services helps from application to graduation.","bodyHtml":"<p>China has become one of the most popular study destinations for Sri Lankan students — recognised universities, English-taught programs, lower costs than many Western countries and generous scholarships. This guide walks you through the whole journey, step by step.</p><h2>Why Sri Lankan students choose China</h2><p>Chinese universities offer internationally recognised degrees across engineering, business, IT, medicine and the sciences, many of them taught fully in English. Tuition and living costs are generally lower than in the UK, Australia or the USA, and the Chinese Government and individual universities offer scholarships specifically for international students.</p><p>Sri Lanka and China also have strong educational and economic ties, so graduates who understand both countries — and speak some Chinese — are in demand for careers in trade, tourism, technology and infrastructure.</p><h2>Programs you can study</h2><ul><li>Diploma and foundation programs</li><li>Bachelor''s degrees (usually 4 years; medicine longer)</li><li>Master''s and PhD programs</li><li>Chinese language programs (from beginner to advanced, with HSK preparation)</li><li>English-taught MBBS / clinical medicine at approved universities</li></ul><h2>General entry requirements</h2><p>For a bachelor''s degree you will normally need your G.C.E. Advanced Level (A/L) results, a valid passport, a medical examination record and proof of English ability for English-taught programs (or HSK for Chinese-taught programs). Master''s applicants need a recognised bachelor''s degree and usually recommendation letters and a study plan.</p><p>Exact requirements differ by university and program, so always check the specific program before applying — this is one of the things Proton checks for you.</p><h2>Step by step: from Sri Lanka to a Chinese campus</h2><ul><li>Choose your subject, level and preferred city or university.</li><li>Prepare documents: passport, A/L or degree certificates and transcripts, photos, medical form, and any language certificate.</li><li>Apply to the university (and for a scholarship, if eligible).</li><li>Receive your admission letter and the JW201/JW202 visa form from the university.</li><li>Apply for your student visa (X1 for long programs) through the Chinese Embassy/visa centre in Colombo.</li><li>Travel to China, register at the university and, with an X1 visa, apply for your residence permit after arrival.</li></ul><h2>How Proton Education Services helps</h2><p>Proton is a licensed Sri Lankan company with partners and offices across China. We help you choose the right university and program, prepare and submit applications, apply for scholarships, get your student visa and settle in after you arrive — so you deal with one trusted team from application to graduation.</p>","faq":[{"q":"Can Sri Lankan students study in China in English?","a":"Yes. Many Chinese universities offer full degree programs taught in English, including business, engineering, IT and medicine (MBBS). Chinese-taught programs are also available if you complete a Chinese language course first."},{"q":"What qualifications do I need to study in China from Sri Lanka?","a":"For a bachelor''s degree you usually need your A/L results, a valid passport and a medical record; English-taught programs may ask for proof of English. Master''s programs need a recognised bachelor''s degree. Requirements vary by university."},{"q":"Which visa do I need to study in China?","a":"Students on programs longer than 180 days apply for an X1 student visa; shorter programs use an X2 visa. You need the admission letter and JW201/JW202 form from your university to apply."},{"q":"Are there scholarships for Sri Lankan students in China?","a":"Yes — the Chinese Government (CSC) Scholarship and many university and provincial scholarships are open to Sri Lankan students. Some cover tuition, accommodation and a monthly stipend."}]}}'),
    (N'what-to-do-after-al-sri-lanka', 2, N'{"en":{"title":"What to Do After A/L in Sri Lanka: Your Options Explained","seoTitle":"What to Do After A/L in Sri Lanka — Study Options | Proton","description":"Finished your G.C.E. Advanced Level? Compare your options after A/L in Sri Lanka — state universities, private degrees, vocational routes and studying abroad in China — and how to choose.","bodyHtml":"<p>Getting your A/L results is a big moment — and a confusing one. Whether or not you are selected for a state university, you have more options than you might think. Here is a clear look at each path.</p><h2>1. Sri Lankan state universities</h2><p>Admission to state universities is through the University Grants Commission (UGC), based on your A/L results and Z-score. Places are limited, so many qualified students are not selected for the course they want even with good results.</p><h2>2. Private and external degrees in Sri Lanka</h2><p>Private institutes offer local and foreign-affiliated degrees. Check that the qualification is recognised (for example by the UGC or the awarding foreign university) and compare total costs carefully.</p><h2>3. Vocational and professional qualifications</h2><p>Diplomas, NVQ qualifications and professional courses (accounting, IT, hospitality and more) can lead straight into work or into a degree later.</p><h2>4. Study abroad — why China is a strong choice</h2><p>Studying abroad gives you an internationally recognised degree, global experience and a second language. China stands out for Sri Lankan students because of recognised universities, English-taught programs, lower costs than many Western countries and scholarships such as the Chinese Government (CSC) Scholarship.</p><p>Popular choices after A/L include engineering, IT, business, international trade, medicine (MBBS) and Chinese language programs that open doors to careers between Sri Lanka and China.</p><h2>How to choose</h2><ul><li>What subject do you genuinely want to study, and what careers does it lead to?</li><li>What is your total budget (tuition, living, travel) — and could a scholarship cover part of it?</li><li>Is the qualification recognised where you want to work?</li><li>Do you want international experience and a second language?</li></ul>","faq":[{"q":"What can I do after A/L if I am not selected for a state university?","a":"You can study for a private or foreign-affiliated degree, take a vocational or professional qualification, or study abroad — for example a bachelor’s degree in China, where English-taught programs and scholarships are available to Sri Lankan students."},{"q":"Can I study in China with my A/L results?","a":"Yes. Chinese universities accept G.C.E. A/L results for bachelor''s programs. Requirements depend on the university and subject; Proton Education Services can check which programs match your results."},{"q":"Which subjects are popular for Sri Lankan students in China?","a":"Engineering, IT and computer science, business and international trade, medicine (MBBS) and Chinese language are among the most popular choices."}]}}'),
    (N'china-student-visa-sri-lanka', 3, N'{"en":{"title":"China Student Visa for Sri Lankans (X1 & X2): How to Apply","seoTitle":"China Student Visa for Sri Lankans (X1/X2) — How to Apply | Proton","description":"How Sri Lankan students apply for a China student visa: the difference between X1 and X2 visas, required documents (admission letter, JW201/JW202), the application steps in Colombo and the residence permit after arrival.","bodyHtml":"<p>Once you have a university offer, the next step is your student visa. Here is how the China student visa works for Sri Lankan students and what you need to prepare.</p><h2>X1 or X2 — which student visa do you need?</h2><ul><li>X1 visa: for study programs longer than 180 days (degrees, long language programs). You convert it into a residence permit after arriving in China.</li><li>X2 visa: for short programs of 180 days or less (short courses, exchanges, summer schools).</li></ul><h2>Documents you will usually need</h2><ul><li>Valid passport (with enough validity and blank pages) and a recent photo</li><li>Completed visa application form</li><li>Original admission letter from the Chinese university</li><li>JW201 or JW202 “Visa Application for Study in China” form (issued by the university)</li><li>Physical examination record for X1 visas (for stays over 6 months)</li></ul><h2>Application steps</h2><ul><li>Receive your admission letter and JW201/JW202 form from the university.</li><li>Complete the online visa application form and book an appointment.</li><li>Submit documents to the Chinese visa application service in Colombo and pay the fee.</li><li>Collect your passport with the visa.</li><li>For an X1 visa, apply for a residence permit at the local public security bureau after arriving in China (usually within 30 days).</li></ul><h2>Proton visa support</h2><p>Proton helps you check every document, complete the forms correctly and prepare for the residence-permit step after arrival — reducing delays and rejections. Visa rules can change, so we always confirm the latest requirements before you apply.</p>","faq":[{"q":"What is the difference between an X1 and an X2 visa?","a":"X1 is for study longer than 180 days and is converted into a residence permit in China; X2 is for study of 180 days or less."},{"q":"What is a JW202 form?","a":"The JW201/JW202 is the official \"Visa Application for Study in China\" form issued by your Chinese university with the admission letter. You need it to apply for a student visa."},{"q":"Where do Sri Lankans apply for a China student visa?","a":"Through the Chinese Embassy’s visa application service in Colombo. Proton Education Services can guide you through the documents and the appointment."}]}}'),
    (N'chinese-government-scholarship-sri-lanka', 4, N'{"en":{"title":"Chinese Government (CSC) Scholarship for Sri Lankan Students","seoTitle":"Chinese Government (CSC) Scholarship for Sri Lankans | Proton","description":"How Sri Lankan students can win a Chinese Government (CSC) Scholarship and other China scholarships: what they cover, who can apply, how to apply and tips for a strong application.","bodyHtml":"<p>Scholarships can make studying in China very affordable. The best known is the Chinese Government Scholarship, administered by the China Scholarship Council (CSC), and there are many university and provincial scholarships too.</p><h2>What a full CSC scholarship can cover</h2><ul><li>Tuition fees</li><li>University accommodation</li><li>A monthly living allowance (stipend)</li><li>Comprehensive medical insurance</li></ul><h2>Types of scholarships in China</h2><ul><li>Chinese Government Scholarship (CSC) — bilateral and university programs</li><li>Provincial and city government scholarships</li><li>University scholarships (full or partial tuition waivers)</li><li>Confucius Institute scholarships for Chinese language study</li></ul><h2>How to apply</h2><ul><li>Choose your program and check the university accepts scholarship applicants.</li><li>Prepare documents: certificates and transcripts, study plan or research proposal, recommendation letters, passport and medical form.</li><li>Submit the online CSC application and the university application before the deadline (applications usually open early in the year).</li><li>Wait for the result and your admission notice and visa form.</li></ul><h2>Tips for a strong application</h2><ul><li>Apply early — deadlines are strict.</li><li>Write a clear, specific study plan that links your goals to the program.</li><li>Get recommendation letters from teachers or lecturers who know your work.</li><li>Make sure every document is complete and consistent.</li></ul>","faq":[{"q":"Can Sri Lankan students get a Chinese Government Scholarship?","a":"Yes. Sri Lankan students can apply for the Chinese Government (CSC) Scholarship as well as university and provincial scholarships."},{"q":"What does the CSC scholarship cover?","a":"A full scholarship usually covers tuition, accommodation, a monthly stipend and medical insurance; partial scholarships cover some of these."},{"q":"When should I apply for a China scholarship?","a":"Most scholarship applications open early in the year for September intake, so start preparing several months before."}]}}'),
    (N'mbbs-in-china-sri-lanka', 5, N'{"en":{"title":"Study Medicine (MBBS) in China from Sri Lanka","seoTitle":"MBBS in China for Sri Lankan Students — Guide | Proton Education","description":"A guide for Sri Lankan students considering MBBS in China: English-taught clinical medicine, choosing an approved university, entry requirements and practising in Sri Lanka afterwards (SLMC and the ERPM exam).","bodyHtml":"<p>Medicine is one of the most popular reasons Sri Lankan students go to China. Choosing the right university matters more than anything else — here is what to look for.</p><h2>English-taught MBBS in China</h2><p>China''s Ministry of Education approves a list of universities that may teach clinical medicine (MBBS) in English to international students. Programs typically last six years, including a clinical internship.</p><h2>Choosing the right university</h2><ul><li>Make sure the university is approved to teach MBBS in English to international students.</li><li>Check recognition by the Sri Lanka Medical Council (SLMC) and the World Directory of Medical Schools.</li><li>Look at clinical training: teaching hospitals and patient exposure.</li><li>Compare total cost, location and support for international students.</li></ul><h2>Practising medicine in Sri Lanka afterwards</h2><p>Graduates of foreign medical schools must meet the Sri Lanka Medical Council (SLMC) requirements to register, which include passing the Examination for Registration to Practise Medicine (ERPM). Always confirm the current SLMC rules before you choose a university.</p>","faq":[{"q":"Is an MBBS from China valid in Sri Lanka?","a":"Graduates can practise in Sri Lanka after meeting Sri Lanka Medical Council (SLMC) requirements, including passing the ERPM exam. Choose an approved university and check current SLMC rules first."},{"q":"How long is MBBS in China?","a":"English-taught MBBS programs in China usually take six years, including a one-year internship."},{"q":"Do I need to know Chinese to study MBBS in China?","a":"The program is taught in English, but universities usually include Chinese language classes because you will talk with patients during clinical training."}]}}'),
    (N'learn-chinese-hsk-sri-lanka', 6, N'{"en":{"title":"Learn Chinese & the HSK Exam: A Guide for Sri Lankans","seoTitle":"Learn Chinese & HSK Guide for Sri Lankan Students | Proton","description":"Why Chinese language skills matter for Sri Lankan students and professionals, how the HSK levels work, Chinese language programs in China and how HSK helps with admissions and scholarships.","bodyHtml":"<p>Chinese is a valuable skill for any Sri Lankan student or professional working with China. The HSK exam is the standard way to prove your level.</p><h2>What is the HSK?</h2><p>The HSK (Hanyu Shuiping Kaoshi) is the official Chinese proficiency test for non-native speakers. Higher levels show stronger reading, listening and writing skills. Chinese-taught degree programs and some scholarships ask for a minimum HSK level.</p><h2>Ways to learn Chinese</h2><ul><li>Chinese language programs at universities in China (one semester to one year or more)</li><li>Language-plus-degree pathways: a language year followed by a Chinese-taught degree</li><li>Courses in Sri Lanka before you travel</li></ul><h2>Why it matters</h2><ul><li>Opens Chinese-taught degree programs and more scholarships</li><li>Makes daily life and clinical or internship placements in China easier</li><li>Valuable for careers in trade, tourism, logistics and technology between Sri Lanka and China</li></ul>","faq":[{"q":"What HSK level do I need for a Chinese-taught degree?","a":"It depends on the university and subject; many undergraduate programs ask for a mid-level HSK. English-taught programs do not require HSK."},{"q":"Can I study a Chinese language program in China?","a":"Yes — universities across China offer Chinese language programs for international students, from one semester to a full year or longer."}]}}')
END
GO
