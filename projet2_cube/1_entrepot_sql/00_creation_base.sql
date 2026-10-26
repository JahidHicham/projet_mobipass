-- MobiPass - Projet 2 : création de la base MobiPass (sur votre PC uniquement)
-- À la fac (etu-mssql3), ne pas lancer ce script : utiliser votre base personnelle (numéro étudiant).
IF DB_ID(N'MobiPass') IS NULL
    CREATE DATABASE MobiPass;
GO
SELECT name AS base_creee, create_date FROM sys.databases WHERE name = N'MobiPass';
GO
