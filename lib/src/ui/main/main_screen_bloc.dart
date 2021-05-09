import 'dart:async';

import 'package:feather/src/model/internal/application_error.dart';
import 'package:feather/src/model/internal/geo_position.dart';
import 'package:feather/src/model/remote/weather_forecast_list_response.dart';
import 'package:feather/src/model/remote/weather_response.dart';
import 'package:feather/src/resources/location_manager.dart';
import 'package:feather/src/resources/repository/local/application_local_repository.dart';
import 'package:feather/src/resources/repository/local/weather_local_repository.dart';
import 'package:feather/src/resources/repository/remote/weather_remote_repository.dart';
import 'package:feather/src/ui/main/main_screen_event.dart';
import 'package:feather/src/utils/app_logger.dart';
import 'package:feather/src/utils/date_time_helper.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';

import 'main_screen_state.dart';

class MainScreenBloc extends Bloc<MainScreenEvent, MainScreenState> {
  final LocationManager _locationManager;
  final WeatherLocalRepository _weatherLocalRepository;
  final WeatherRemoteRepository _weatherRemoteRepository;
  final ApplicationLocalRepository _applicationLocalRepository;
  Timer? _refreshTimer;

  MainScreenBloc(
    this._locationManager,
    this._weatherLocalRepository,
    this._weatherRemoteRepository,
    this._applicationLocalRepository,
  ) : super(InitialMainScreenState());

  @override
  Stream<MainScreenState> mapEventToState(MainScreenEvent event) async* {
    if (event is LocationCheckMainScreenEvent) {
      yield CheckingLocationState();
      if (!await _checkLocationServiceEnabled()) {
        yield LocationServiceDisabledMainScreenState();
      } else if (!await _checkPermission()) {
        yield PermissionNotGrantedMainScreenState();
      } else {
        yield* _selectWeatherData();
      }
    }
    if (event is LoadWeatherDataMainScreenEvent) {
      yield* _selectWeatherData();
    }
  }

  Stream<MainScreenState> _selectWeatherData() async* {
    yield LoadingMainScreenState();

    final GeoPosition? position = await _getPosition();
    Log.i("Got geo position: $position");
    if (position != null) {
      final WeatherResponse? weatherResponse =
          await _fetchWeather(position.lat, position.long);
      final WeatherForecastListResponse? weatherForecastListResponse =
          await _fetchWeatherForecast(position.lat, position.long);
      _saveLastRefreshTime();
      if (weatherResponse != null && weatherForecastListResponse != null) {
        if (weatherResponse.errorCode != null) {
          yield FailedLoadMainScreenState(weatherResponse.errorCode!);
        } else {
          yield SuccessLoadMainScreenState(
              weatherResponse, weatherForecastListResponse);
          _setupRefreshTimer();
        }
      } else {
        yield const FailedLoadMainScreenState(ApplicationError.connectionError);
      }
    } else {
      yield const FailedLoadMainScreenState(
          ApplicationError.locationNotSelectedError);
    }
  }

  Future<bool> _checkLocationServiceEnabled() async {
    return Geolocator.isLocationServiceEnabled();
  }

  Future<bool> _checkPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } else if (permission == LocationPermission.deniedForever) {
      return false;
    } else {
      return true;
    }
  }

  Future<GeoPosition?> _getPosition() async {
    try {
      final positionOptional = await _locationManager.getLocation();
      if (positionOptional.isPresent) {
        Log.i("Position is present!");
        final position = positionOptional.value!;
        final GeoPosition geoPosition = GeoPosition.fromPosition(position);
        _weatherLocalRepository.saveLocation(geoPosition);
        return geoPosition;
      } else {
        Log.i("Position is not present!");
        return _weatherLocalRepository.getLocation();
      }
    } catch (error, stackTrace) {
      Log.e("getPosition failed", error: error, stackTrace: stackTrace);
      return null;
    }
  }

  Future<WeatherResponse?> _fetchWeather(
      double? latitude, double? longitude) async {
    Log.i("Fetch weather");
    final WeatherResponse weatherResponse =
        await _weatherRemoteRepository.fetchWeather(latitude, longitude);
    if (weatherResponse.errorCode == null) {
      _weatherLocalRepository.saveWeather(weatherResponse);
      return weatherResponse;
    } else {
      Log.i("Selected weather from storage");
      final WeatherResponse? weatherResponseStorage =
          await _weatherLocalRepository.getWeather();
      if (weatherResponseStorage != null) {
        return weatherResponseStorage;
      } else {
        return weatherResponse;
      }
    }
  }

  void _saveLastRefreshTime() {
    _applicationLocalRepository
        .saveLastRefreshTime(DateTimeHelper.getCurrentTime());
  }

  void _setupRefreshTimer() {
    Log.i("Setup refresh data timer");
    _refreshTimer?.cancel();
    const duration = Duration(minutes: 30);
    _refreshTimer = Timer(duration, () {
      add(LoadWeatherDataMainScreenEvent());
    });
  }

  Future<WeatherForecastListResponse?> _fetchWeatherForecast(
      double? latitude, double? longitude) async {
    //lastRequestTime = DateTime.now().millisecondsSinceEpoch;

    WeatherForecastListResponse weatherForecastResponse =
        await _weatherRemoteRepository.fetchWeatherForecast(
            latitude, longitude);
    if (weatherForecastResponse.errorCode == null) {
      _weatherLocalRepository.saveWeatherForecast(weatherForecastResponse);
    } else {
      WeatherForecastListResponse? weatherForecastResponseStorage =
          await _weatherLocalRepository.getWeatherForecast();
      if (weatherForecastResponseStorage != null) {
        weatherForecastResponse = weatherForecastResponseStorage;
        //_logger.info("Using weather forecast data from storage");
      }
    }
    return weatherForecastResponse;
  }

  @override
  Future<void> close() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    return super.close();
  }
}
