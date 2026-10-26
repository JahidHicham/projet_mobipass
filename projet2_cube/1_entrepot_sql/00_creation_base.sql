-- MobiPass - Projet 2 : création de la base MobiPass (sur votre PC uniquement)
-- À la fac (etu-mssql3), ne pas lancer ce script : utiliser votre base personnelle (numéro étudiant).
-- Sécurité : le script s'arrête si le serveur SQL n'est pas sur le PC où vous êtes (serveur distant).

IF UPPER(CAST(SERVERPROPERTY('MachineName') AS NVARCHAR(128))) <> UPPER(HOST_NAME())
BEGIN
    RAISERROR(N'Ce script crée la base MobiPass seulement sur votre propre PC (localhost). Sur un serveur distant comme etu-mssql3, utilisez votre base personnelle.', 16, 1);
    SET NOEXEC ON;   -- la suite du script n'est pas exécutée
END
GO
IF DB_ID(N'MobiPass') IS NULL
    CREATE DATABASE MobiPass;
GO
SELECT name AS base_creee, create_date FROM sys.databases WHERE name = N'MobiPass';
GO
SET NOEXEC OFF;
GO
