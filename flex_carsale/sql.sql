CREATE TABLE IF NOT EXISTS `occasion_vehicles` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `seller` varchar(50) DEFAULT NULL,
  `price` int(11) DEFAULT NULL,
  `description` longtext DEFAULT NULL,
  `plate` varchar(50) DEFAULT NULL,
  `model` varchar(50) DEFAULT NULL,
  `mods` text DEFAULT NULL,
  `occasionid` varchar(50) DEFAULT NULL,
  `location` varchar(50) DEFAULT 'city',
  `spotid` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `occasionId` (`occasionid`),
  KEY `location_spot` (`location`,`spotid`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE `occasion_vehicles`
  ADD COLUMN IF NOT EXISTS `location` varchar(50) DEFAULT 'city' AFTER `occasionid`;

ALTER TABLE `occasion_vehicles`
  ADD COLUMN IF NOT EXISTS `spotid` int(11) DEFAULT NULL AFTER `location`;

ALTER TABLE `occasion_vehicles`
  ADD INDEX `location_spot` (`location`,`spotid`);
