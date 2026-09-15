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
  static const double facultyEligibilityRadiusMeters = 100.0;

  static const double evTriggerRadiusMeters = 35.0;

  // ---------------------------------------------------------------------------
  // PICKUP POINTS
  // ---------------------------------------------------------------------------

  static const LatLng ab1Pickup = LatLng(12.844326005876631, 80.15326191418521);

  static const LatLng ab3Pickup = LatLng(12.844538118695052, 80.15486733537958);

  static const LatLng ab2Pickup = LatLng(12.843668573583829, 80.15643177150962);

  static const LatLng mab3Pickup = LatLng(12.8437876689543, 80.15813367748207);

  static const LatLng mab4Pickup = LatLng(
    12.844349384460841,
    80.15834657729486,
  );

  static const LatLng ab5Pickup = LatLng(12.84136735419787, 80.15522444785671);

  // ---------------------------------------------------------------------------
  // BLOCK LOCATIONS
  // ---------------------------------------------------------------------------

  static const LatLng ab1Block = LatLng(12.84391293192312, 80.15342317676296);

  static const LatLng ab2Block = LatLng(12.843120555928554, 80.15645139066287);

  static const LatLng ab3Block = LatLng(12.844043686792524, 80.15474014135296);

  static const LatLng ab4Block = LatLng(12.843127357629559, 80.1554401593973);

  static const LatLng adbBlock = LatLng(12.840719876775859, 80.15393816088053);

  static const LatLng mab3Block = LatLng(12.843815126711887, 80.15826228341854);

  static const LatLng mab4Block = LatLng(12.844269518303292, 80.15844785968386);

  static const LatLng ab5Block = LatLng(12.840988937758677, 80.15540443366967);

  // ---------------------------------------------------------------------------
  // CAMPUS STOPS
  //
  // These are the locations used for EV arrival detection.
  //
  // AB4 uses AB2 pickup because AB4 faculty are associated with
  // the AB2 pickup point.
  //
  // ADB is NOT included because it is marking-only.
  // ---------------------------------------------------------------------------

  static const List<CampusStop> campusStops = [
    CampusStop(name: 'AB1', blockPosition: ab1Block, pickupPosition: ab1Pickup),
    CampusStop(name: 'AB3', blockPosition: ab3Block, pickupPosition: ab3Pickup),
    CampusStop(name: 'AB2', blockPosition: ab2Block, pickupPosition: ab2Pickup),
    CampusStop(name: 'AB4', blockPosition: ab4Block, pickupPosition: ab2Pickup),
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

  // ---------------------------------------------------------------------------
  // ACTUAL PICKUP POINTS
  //
  // AB4 has NO separate pickup point.
  // AB4 faculty use the AB2 pickup point.
  //
  // ADB is marking-only and is not a pickup point.
  // ---------------------------------------------------------------------------

  static const List<LatLng> pickupPoints = [
    ab1Pickup,
    ab3Pickup,
    ab2Pickup,
    mab3Pickup,
    mab4Pickup,
    ab5Pickup,
  ];

  static const List<String> pickupNames = [
    'AB1',
    'AB3',
    'AB2',
    'MAB3',
    'MAB4',
    'AB5',
  ];

  // ---------------------------------------------------------------------------
  // BUGGY ROAD
  // ---------------------------------------------------------------------------

  static const List<LatLng> buggyRoad = [
    LatLng(12.8443355, 80.1532232),
    LatLng(12.8443920, 80.1533047),
    LatLng(12.8444464, 80.1534013),
    LatLng(12.8444966, 80.1534935),
    LatLng(12.8445468, 80.1535965),
    LatLng(12.8445656, 80.1536995),
    LatLng(12.8445928, 80.1538433),
    LatLng(12.8446012, 80.1539527),
    LatLng(12.8446095, 80.1540643),
    LatLng(12.8446388, 80.1541780),
    LatLng(12.8446597, 80.1542896),
    LatLng(12.8446493, 80.1544291),
    LatLng(12.8446409, 80.1545471),
    LatLng(12.8446263, 80.1546737),
    LatLng(12.8446137, 80.1547724),
    LatLng(12.8445991, 80.1548303),
    LatLng(12.8445635, 80.1548883),
    LatLng(12.8445217, 80.1549462),
    LatLng(12.8444631, 80.1550406),
    LatLng(12.8443961, 80.1551436),
    LatLng(12.8443313, 80.1552445),
    LatLng(12.8442748, 80.1553303),
    LatLng(12.8442204, 80.1554076),
    LatLng(12.8441576, 80.1554805),
    LatLng(12.8441179, 80.1555857),
    LatLng(12.8440802, 80.1556951),
    LatLng(12.8440468, 80.1557874),
    LatLng(12.8440133, 80.1558989),
    LatLng(12.8439652, 80.1560127),
    LatLng(12.8439212, 80.1560942),
    LatLng(12.8438710, 80.1561500),
    LatLng(12.8437999, 80.1562294),
    LatLng(12.8437539, 80.1562830),
    LatLng(12.8436995, 80.1563517),
    LatLng(12.8436409, 80.1564161),
    LatLng(12.8435844, 80.1564912),
    LatLng(12.8435572, 80.1565727),
    LatLng(12.8435133, 80.1566907),
    LatLng(12.8434714, 80.1568002),
    LatLng(12.8434275, 80.1568881),
    LatLng(12.8433815, 80.1569890),
    LatLng(12.8433689, 80.1570319),
    LatLng(12.8433815, 80.1570813),
    LatLng(12.8433836, 80.1571306),
    LatLng(12.8433731, 80.1571499),
    LatLng(12.8433334, 80.1572315),
    LatLng(12.8433187, 80.1572958),
    LatLng(12.8433250, 80.1573559),
    LatLng(12.8433961, 80.1573988),
    LatLng(12.8434861, 80.1574482),
    LatLng(12.8435447, 80.1574975),
    LatLng(12.8435530, 80.1575598),
    LatLng(12.8435133, 80.1576499),
    LatLng(12.8434463, 80.1578022),
    LatLng(12.8433836, 80.1579524),
    LatLng(12.8433689, 80.1579868),
    LatLng(12.8434861, 80.1580361),
    LatLng(12.8436074, 80.1580855),
    LatLng(12.8437309, 80.1581327),
    LatLng(12.8438187, 80.1581606),
    LatLng(12.8439568, 80.1582099),
    LatLng(12.8440656, 80.1582528),
    LatLng(12.8441639, 80.1582958),
    LatLng(12.8442926, 80.1583371),
    LatLng(12.8443805, 80.1583628),
    LatLng(12.8444160, 80.1583542),
    LatLng(12.8444558, 80.1583628),
    LatLng(12.8444432, 80.1583950),
    LatLng(12.8444077, 80.1583886),
    LatLng(12.8443386, 80.1583478),
    LatLng(12.8442110, 80.1583113),
    LatLng(12.8441085, 80.1582727),
    LatLng(12.8439871, 80.1582233),
    LatLng(12.8438784, 80.1581804),
    LatLng(12.8437696, 80.1581482),
    LatLng(12.8436629, 80.1581075),
    LatLng(12.8435332, 80.1580560),
    LatLng(12.8434244, 80.1580131),
    LatLng(12.8433679, 80.1579873),
    LatLng(12.8434307, 80.1578435),
    LatLng(12.8434997, 80.1576933),
    LatLng(12.8435353, 80.1575925),
    LatLng(12.8435520, 80.1575303),
    LatLng(12.8435311, 80.1574788),
    LatLng(12.8435039, 80.1574573),
    LatLng(12.8434348, 80.1574144),
    LatLng(12.8433574, 80.1573736),
    LatLng(12.8433093, 80.1573328),
    LatLng(12.8433302, 80.1572599),
    LatLng(12.8433532, 80.1571869),
    LatLng(12.8433867, 80.1570968),
    LatLng(12.8433637, 80.1570389),
    LatLng(12.8433072, 80.1570024),
    LatLng(12.8428365, 80.1567749),
    LatLng(12.8424437, 80.1565947),
    LatLng(12.8423412, 80.1565303),
    LatLng(12.8422722, 80.1564810),
    LatLng(12.8421989, 80.1564080),
    LatLng(12.8421090, 80.1562986),
    LatLng(12.8420096, 80.1561698),
    LatLng(12.8419678, 80.1560883),
    LatLng(12.8419175, 80.1559960),
    LatLng(12.8418443, 80.1559166),
    LatLng(12.8417732, 80.1558308),
    LatLng(12.8417167, 80.1557579),
    LatLng(12.8416372, 80.1556484),
    LatLng(12.8415828, 80.1555497),
    LatLng(12.8414510, 80.1553480),
    LatLng(12.8414104, 80.1552648),
    LatLng(12.8413822, 80.1552144),
    LatLng(12.8413215, 80.1552337),
    LatLng(12.8412436, 80.1552746),
  ];

  // ---------------------------------------------------------------------------
  // DISTANCE / GEOFENCING
  // ---------------------------------------------------------------------------

  final Distance _distance = const Distance();

  double distanceBetween(LatLng first, LatLng second) {
    return _distance.as(LengthUnit.Meter, first, second);
  }

  CampusStop? findFacultyBlock(LatLng facultyPosition) {
    for (final stop in campusStops) {
      final distanceToBlock = distanceBetween(
        facultyPosition,
        stop.blockPosition,
      );

      final distanceToPickup = distanceBetween(
        facultyPosition,
        stop.pickupPosition,
      );

      if (distanceToBlock <= facultyEligibilityRadiusMeters ||
          distanceToPickup <= facultyEligibilityRadiusMeters) {
        return stop;
      }
    }

    return null;
  }

  bool isEvNearStop(LatLng evPosition, CampusStop stop) {
    final distanceToBlock = distanceBetween(evPosition, stop.blockPosition);

    final distanceToPickup = distanceBetween(evPosition, stop.pickupPosition);

    return distanceToBlock <= evTriggerRadiusMeters ||
        distanceToPickup <= evTriggerRadiusMeters;
  }
}
