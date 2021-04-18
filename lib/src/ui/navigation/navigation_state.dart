import 'package:equatable/equatable.dart';
import 'package:feather/src/models/internal/navigation_route.dart';

class NavigationState extends Equatable {
  final NavigationRoute navigationRoute;

  const NavigationState(this.navigationRoute);

  @override
  List<Object> get props => [
        navigationRoute,
      ];
}
