import 'package:latlong2/latlong.dart';

class CampusStop {
  const CampusStop({
    required this.name,
    required this.blockPosition,
    required this.pickupPosition,
  });

  final String name;
  final LatLng blockPosition;
  final LatLng pickupPosition;
}

class EvTrackingService {
  // ---------------------------------------------------------------------------
  // ELIGIBILITY RADII & BOUNDARY CENTERS
  // ---------------------------------------------------------------------------

  static const LatLng ab24EligibilityCenter = LatLng(
    12.843032299736574,
    80.1557585034112,
  );

  static const double ab1EligibilityRadiusMeters = 75.0;
  static const double ab3EligibilityRadiusMeters = 75.0;
  static const double mab3EligibilityRadiusMeters = 25.0;
  static const double mab4EligibilityRadiusMeters = 25.0;
  static const double ab5EligibilityRadiusMeters = 50.0;
  static const double ab24EligibilityRadiusMeters = 115.0;

  static const double evTriggerRadiusMeters = 35.0;

  // ---------------------------------------------------------------------------
  // PICKUP LOCATIONS
  // ---------------------------------------------------------------------------

  static const LatLng ab1Pickup = LatLng(12.844326005876631, 80.15326191418521);
  static const LatLng ab3Pickup = LatLng(12.844538118695052, 80.15486733537958);
  static const LatLng ab24Pickup = LatLng(
    12.843668573583829,
    80.15643177150962,
  );
  static const LatLng mab3Pickup = LatLng(12.8437876689543, 80.15813367748207);
  static const LatLng mab4Pickup = LatLng(
    12.844349384460841,
    80.15834657729486,
  );
  static const LatLng ab5Pickup = LatLng(12.84136735419787, 80.15522444785671);

  // ---------------------------------------------------------------------------
  // BUILDING BLOCK LOCATIONS
  // ---------------------------------------------------------------------------

  static const LatLng ab1Block = LatLng(12.84391293192312, 80.15342317676296);
  static const LatLng ab2Block = LatLng(12.843120555928554, 80.15645139066287);
  static const LatLng ab3Block = LatLng(12.844043686792524, 80.15474014135296);
  static const LatLng ab4Block = LatLng(12.843127357629559, 80.1554401593973);
  static const LatLng adbBlock = LatLng(12.840719876775859, 80.15393816088053);
  static const LatLng mab3Block = LatLng(12.843767571559695, 80.15830467978871);
  static const LatLng mab4Block = LatLng(12.84418012520221, 80.15850155316652);
  static const LatLng ab5Block = LatLng(12.84099011726808, 80.15540376140352);

  // ---------------------------------------------------------------------------
  // CAMPUS STOPS DEFINITION
  // ---------------------------------------------------------------------------

  static const List<CampusStop> campusStops = [
    CampusStop(name: 'AB1', blockPosition: ab1Block, pickupPosition: ab1Pickup),
    CampusStop(name: 'AB3', blockPosition: ab3Block, pickupPosition: ab3Pickup),
    CampusStop(
      name: 'AB2-4',
      blockPosition: ab2Block,
      pickupPosition: ab24Pickup,
    ),
    CampusStop(
      name: 'MAB3',
      blockPosition: mab3Block,
      pickupPosition: mab3Pickup,
    ),
    CampusStop(
      name: 'MAB4',
      blockPosition: mab4Block,
      pickupPosition: mab4Pickup,
    ),
    CampusStop(name: 'AB5', blockPosition: ab5Block, pickupPosition: ab5Pickup),
  ];

  static const List<LatLng> pickupPoints = [
    ab1Pickup,
    ab3Pickup,
    ab24Pickup,
    mab3Pickup,
    mab4Pickup,
    ab5Pickup,
  ];

  static const List<String> pickupNames = [
    'AB1',
    'AB3',
    'AB2-4',
    'MAB3',
    'MAB4',
    'AB5',
  ];

  // ---------------------------------------------------------------------------
  // CAMPUS ROAD PATH WAYPOINTS (DUAL ROUTE LOOPS)
  // ---------------------------------------------------------------------------

  static const List<LatLng> buggyRoadYellow = [
    LatLng(12.8443161, 80.1532332),
    LatLng(12.8443444, 80.1532696),
    LatLng(12.8443768, 80.1533083),
    LatLng(12.8444061, 80.1533437),
    LatLng(12.8444270, 80.1533737),
    LatLng(12.8444464, 80.1534067),
    LatLng(12.8444657, 80.1534531),
    LatLng(12.8444877, 80.1535003),
    LatLng(12.8445044, 80.1535550),
    LatLng(12.8445253, 80.1536162),
    LatLng(12.8445358, 80.1536816),
    LatLng(12.8445389, 80.1537353),
    LatLng(12.8445483, 80.1537846),
    LatLng(12.8445525, 80.1538211),
    LatLng(12.8445546, 80.1538554),
    LatLng(12.8445609, 80.1539016),
    LatLng(12.8445640, 80.1539456),
    LatLng(12.8445755, 80.1539885),
    LatLng(12.8445923, 80.1540346),
    LatLng(12.8445996, 80.1540786),
    LatLng(12.8446080, 80.1541322),
    LatLng(12.8446163, 80.1541923),
    LatLng(12.8446247, 80.1542385),
    LatLng(12.8446310, 80.1542857),
    LatLng(12.8446331, 80.1543168),
    LatLng(12.8446281, 80.1543801),
    LatLng(12.8446197, 80.1544423),
    LatLng(12.8446114, 80.1544959),
    LatLng(12.8446072, 80.1545582),
    LatLng(12.8446009, 80.1546140),
    LatLng(12.8445925, 80.1546730),
    LatLng(12.8445884, 80.1547116),
    LatLng(12.8445800, 80.1547631),
    LatLng(12.8445706, 80.1548006),
    LatLng(12.8445591, 80.1548436),
    LatLng(12.8445361, 80.1548768),
    LatLng(12.8445130, 80.1549090),
    LatLng(12.8444827, 80.1549455),
    LatLng(12.8444513, 80.1549852),
    LatLng(12.8444199, 80.1550302),
    LatLng(12.8443938, 80.1550753),
    LatLng(12.8443614, 80.1551247),
    LatLng(12.8443342, 80.1551676),
    LatLng(12.8443049, 80.1552126),
    LatLng(12.8442766, 80.1552555),
    LatLng(12.8442494, 80.1552974),
    LatLng(12.8442139, 80.1553489),
    LatLng(12.8441718, 80.1554009),
    LatLng(12.8441404, 80.1554567),
    LatLng(12.8441038, 80.1555168),
    LatLng(12.8440829, 80.1555747),
    LatLng(12.8440630, 80.1556294),
    LatLng(12.8440463, 80.1556831),
    LatLng(12.8440306, 80.1557464),
    LatLng(12.8440086, 80.1558086),
    LatLng(12.8439898, 80.1558633),
    LatLng(12.8439730, 80.1559202),
    LatLng(12.8439521, 80.1559846),
    LatLng(12.8439396, 80.1560404),
    LatLng(12.8439212, 80.1560996),
    LatLng(12.8438789, 80.1561380),
    LatLng(12.8438444, 80.1561841),
    LatLng(12.8437973, 80.1562225),
    LatLng(12.8437596, 80.1562611),
    LatLng(12.8437209, 80.1563062),
    LatLng(12.8436791, 80.1563544),
    LatLng(12.8436404, 80.1563995),
    LatLng(12.8436090, 80.1564435),
    LatLng(12.8435713, 80.1564918),
    LatLng(12.8435525, 80.1565433),
    LatLng(12.8435303, 80.1566020),
    LatLng(12.8435094, 80.1566471),
    LatLng(12.8434843, 80.1566996),
    LatLng(12.8434654, 80.1567544),
    LatLng(12.8434435, 80.1568048),
    LatLng(12.8434215, 80.1568541),
    LatLng(12.8434058, 80.1569046),
    LatLng(12.8433954, 80.1569475),
    LatLng(12.8433912, 80.1569689),
    LatLng(12.8433912, 80.1569947),
    LatLng(12.8433985, 80.1570194),
    LatLng(12.8434142, 80.1570376),
    LatLng(12.8434320, 80.1570591),
    LatLng(12.8434377, 80.1571050),
    LatLng(12.8434231, 80.1571394),
    LatLng(12.8434042, 80.1571909),
    LatLng(12.8433854, 80.1572274),
    LatLng(12.8433749, 80.1572660),
    LatLng(12.8433645, 80.1573153),
    LatLng(12.8433645, 80.1573518),
    LatLng(12.8433961, 80.1574042),
    LatLng(12.8434348, 80.1574198),
    LatLng(12.8434670, 80.1574291),
    LatLng(12.8435039, 80.1574627),
    LatLng(12.8435311, 80.1574842),
    LatLng(12.8435447, 80.1575029),
    LatLng(12.8435353, 80.1575979),
    LatLng(12.8435133, 80.1576553),
    LatLng(12.8434795, 80.1577144),
    LatLng(12.8434628, 80.1577659),
    LatLng(12.8434419, 80.1578282),
    LatLng(12.8434272, 80.1578904),
    LatLng(12.8434105, 80.1579440),
    LatLng(12.8434269, 80.1579901),
    LatLng(12.8434586, 80.1580197),
    LatLng(12.8435039, 80.1580350),
    LatLng(12.8435347, 80.1580502),
    LatLng(12.8435985, 80.1580744),
    LatLng(12.8436258, 80.1580848),
    LatLng(12.8436715, 80.1581007),
    LatLng(12.8437143, 80.1581140),
    LatLng(12.8437361, 80.1581233),
    LatLng(12.8437720, 80.1581359),
    LatLng(12.8438067, 80.1581471),
    LatLng(12.8438555, 80.1581631),
    LatLng(12.8438841, 80.1581731),
    LatLng(12.8439206, 80.1581867),
    LatLng(12.8439557, 80.1581991),
    LatLng(12.8439882, 80.1582104),
    LatLng(12.8441344, 80.1582632),
    LatLng(12.8441650, 80.1582769),
    LatLng(12.8441922, 80.1582890),
    LatLng(12.8442162, 80.1582989),
    LatLng(12.8442491, 80.1583129),
    LatLng(12.8442999, 80.1583311),
    LatLng(12.8443687, 80.1583561),
  ];

  static const List<LatLng> buggyRoadOrange = [
    LatLng(12.8443535, 80.1584085),
    LatLng(12.8443001, 80.1583906),
    LatLng(12.8442408, 80.1583649),
    LatLng(12.8442113, 80.1583541),
    LatLng(12.8441543, 80.1583327),
    LatLng(12.8441294, 80.1583263),
    LatLng(12.8441157, 80.1583231),
    LatLng(12.8441046, 80.1583196),
    LatLng(12.8440752, 80.1583083),
    LatLng(12.8440083, 80.1582780),
    LatLng(12.8438872, 80.1582378),
    LatLng(12.8438578, 80.1582289),
    LatLng(12.8438404, 80.1582230),
    LatLng(12.8438188, 80.1582207),
    LatLng(12.8437984, 80.1582074),
    LatLng(12.8437792, 80.1582016),
    LatLng(12.8437539, 80.1581952),
    LatLng(12.8437346, 80.1581850),
    LatLng(12.8437169, 80.1581782),
    LatLng(12.8436972, 80.1581699),
    LatLng(12.8436762, 80.1581640),
    LatLng(12.8436498, 80.1581549),
    LatLng(12.8435687, 80.1581272),
    LatLng(12.8435282, 80.1581109),
    LatLng(12.8434578, 80.1580852),
    LatLng(12.8434146, 80.1580760),
    LatLng(12.8433776, 80.1580556),
    LatLng(12.8433582, 80.1580342),
    LatLng(12.8433477, 80.1579977),
    LatLng(12.8433477, 80.1579440),
    LatLng(12.8433582, 80.1579119),
    LatLng(12.8433791, 80.1578689),
    LatLng(12.8434042, 80.1577960),
    LatLng(12.8434147, 80.1577423),
    LatLng(12.8434335, 80.1576887),
    LatLng(12.8434586, 80.1576222),
    LatLng(12.8434837, 80.1575728),
    LatLng(12.8434879, 80.1575278),
    LatLng(12.8434712, 80.1574891),
    LatLng(12.8434272, 80.1574548),
    LatLng(12.8433875, 80.1574441),
    LatLng(12.8433519, 80.1574162),
    LatLng(12.8433247, 80.1573883),
    LatLng(12.8433093, 80.1573382),
    LatLng(12.8433187, 80.1573012),
    LatLng(12.8433334, 80.1572369),
    LatLng(12.8433498, 80.1571630),
    LatLng(12.8433603, 80.1571179),
    LatLng(12.8433582, 80.1570836),
    LatLng(12.8433436, 80.1570535),
    LatLng(12.8433101, 80.1570321),
    LatLng(12.8432431, 80.1570042),
    LatLng(12.8431992, 80.1569956),
    LatLng(12.8431526, 80.1569720),
    LatLng(12.8430985, 80.1569402),
    LatLng(12.8430450, 80.1569121),
    LatLng(12.8428610, 80.1568243),
    LatLng(12.8426304, 80.1567251),
    LatLng(12.8425540, 80.1566929),
    LatLng(12.8424839, 80.1566650),
    LatLng(12.8424348, 80.1566457),
    LatLng(12.8424076, 80.1566339),
    LatLng(12.8423668, 80.1566092),
    LatLng(12.8422928, 80.1565590),
    LatLng(12.8422258, 80.1565075),
    LatLng(12.8421714, 80.1564582),
    LatLng(12.8421296, 80.1564174),
    LatLng(12.8420961, 80.1563809),
    LatLng(12.8420626, 80.1563316),
    LatLng(12.8420459, 80.1562801),
    LatLng(12.8420020, 80.1562179),
    LatLng(12.8419727, 80.1561578),
    LatLng(12.8419413, 80.1561063),
    LatLng(12.8418890, 80.1560677),
    LatLng(12.8418451, 80.1560140),
    LatLng(12.8417960, 80.1559770),
    LatLng(12.8417593, 80.1559132),
    LatLng(12.8417175, 80.1558574),
    LatLng(12.8416819, 80.1558037),
    LatLng(12.8416400, 80.1557673),
    LatLng(12.8416108, 80.1557158),
    LatLng(12.8415673, 80.1556428),
    LatLng(12.8415276, 80.1555741),
    LatLng(12.8414920, 80.1555183),
    LatLng(12.8414544, 80.1554518),
    LatLng(12.8414167, 80.1553917),
    LatLng(12.8413811, 80.1553231),
    LatLng(12.8413453, 80.1552555),
    LatLng(12.8412781, 80.1552737),
  ];

  // ---------------------------------------------------------------------------
  // DISTANCE & GEOFENCING LOGIC
  // ---------------------------------------------------------------------------

  final Distance _distance = const Distance();

  /// Calculates distance in meters between two coordinates
  double distanceBetween(LatLng first, LatLng second) {
    return _distance.as(LengthUnit.Meter, first, second);
  }

  /// Resolves individual eligibility radius for each stop
  double _eligibilityRadiusForStop(CampusStop stop) {
    switch (stop.name) {
      case 'AB1':
        return ab1EligibilityRadiusMeters;
      case 'AB3':
        return ab3EligibilityRadiusMeters;
      case 'AB2-4':
        return ab24EligibilityRadiusMeters;
      case 'MAB3':
        return mab3EligibilityRadiusMeters;
      case 'MAB4':
        return mab4EligibilityRadiusMeters;
      case 'AB5':
        return ab5EligibilityRadiusMeters;
      default:
        return 50.0;
    }
  }

  /// Identifies which campus stop a faculty member is located in
  CampusStop? findFacultyBlock(LatLng facultyPosition) {
    for (final stop in campusStops) {
      final eligibilityRadius = _eligibilityRadiusForStop(stop);

      // Special check for combined AB2-4 boundary
      if (stop.name == 'AB2-4') {
        final distanceToEligibilityCenter = distanceBetween(
          facultyPosition,
          ab24EligibilityCenter,
        );

        if (distanceToEligibilityCenter <= eligibilityRadius) {
          return stop;
        }
        continue;
      }

      // Standard check against block position and pickup position
      final distanceToBlock = distanceBetween(
        facultyPosition,
        stop.blockPosition,
      );

      final distanceToPickup = distanceBetween(
        facultyPosition,
        stop.pickupPosition,
      );

      if (distanceToBlock <= eligibilityRadius ||
          distanceToPickup <= eligibilityRadius) {
        return stop;
      }
    }

    return null;
  }

  /// Checks if EV buggy has arrived within trigger distance of a stop
  bool isEvNearStop(LatLng evPosition, CampusStop stop) {
    final distanceToBlock = distanceBetween(evPosition, stop.blockPosition);
    final distanceToPickup = distanceBetween(evPosition, stop.pickupPosition);

    return distanceToBlock <= evTriggerRadiusMeters ||
        distanceToPickup <= evTriggerRadiusMeters;
  }
}