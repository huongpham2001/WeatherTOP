import 'dart:async';

import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:weather/models/current_city.dart';
import 'package:weather/models/current_weather.dart';
import 'package:weather/models/weather_of_day.dart';
import 'package:weather/presentation/home_screen/home_screen_cubit/home_screen_states.dart';
import 'package:weather/services/remote/location_api.dart';
import 'package:weather/services/local/shared_preferences.dart';
import 'package:weather/utils/functions/number_converter.dart';
import 'package:weather/utils/template_noti.dart';

import '../../../models/uv_index.dart';
import '../../../services/remote/uv_api.dart';
import '../../../services/remote/weather_api/weather_api.dart';

class HomeScreenCubit extends Cubit<HomeScreenStates> {
  HomeScreenCubit() : super(HomeScreenInitState());

  static HomeScreenCubit get(context) => BlocProvider.of(context);

  Position? positionOfUser;
  //"sliverTitle" Is the name of the current city which will be added into the sliver app bar
  static String sliverTitle = '';
  late CurrentWeather currentWeather;
  late List<UVIndex> uvIndexes;
  late List<double> windIndexes;
  late List<double> humidityIndexes;

  //We use this list to avoid the problem of late currentWeather the problem is an error occurred because the
  //currentWeather is still null when starting the app and we can  not await on initializing
  //the home screen so we set default data then it will change automatically while the right data come
  final List<WeatherOfDay> _listOfDefaults = [
    WeatherOfDay(
      maxTemp: 10,
      currentTemp: 10,
      minTemp: 10,
      feelsLikeTemp: 10,
      humidity: 10,
      windSpeed: 10,
      timeStamp: 10,
      weatherStatus: 'S',
    ),
  ];

  _setCurrentWeatherDefault() {
    return currentWeather = CurrentWeather(
      weatherOfDaysList: _listOfDefaults,
      currentCountryDetails: CurrentCountryDetails(
        currentCountry: 'E',
        currentCity: 'E',
        currentLat: 2,
        currentLon: 10,
        currentSunRise: 10,
        currentSunSet: 10,
      ),
    );
  }

  _setChartDefault() {
    uvIndexes = [];
    windIndexes = [];
    humidityIndexes = [];
    // loop through the list of defaults and add the default data to the chart
    for (int i = 0; i < 6; i++) {
      uvIndexes.add(UVIndex(
        uv: 0,
        date: DateTime.now().add(Duration(days: i)),
      ));
      windIndexes.add(0);
      humidityIndexes.add(0);
    }
  }

  initServices() async {
    //fill the currentWeather with dummy data until the true data come
    _setCurrentWeatherDefault();
    _setChartDefault();

    await _initLocationService();

    await UVAPI.initializeUVAPI();
    if (positionOfUser != null) {
      await _getWeatherApiData();
    }
    _initNotification();
  }

  _setPosition() async {
    positionOfUser = await LocationAPI.getPosition();
  }

  _initLocationService() async {
    int locationCheckingResult = await LocationAPI.getLocation();
    if (locationCheckingResult == LocationAPI.locationServiceIsDisabled) {
      emit(LocationServicesDisabledState());
      debugPrint('Dis');
    } else if (locationCheckingResult == LocationAPI.deniedPermission) {
      emit(DeniedPermissionState());
      debugPrint('Den');
    } else {
      emit(LoadingGettingPositionState());
      await _setPosition();
      emit(LocationSuccessfullySetState());
      debugPrint('Done');
    }
  }

  initWeatherNotification() async {
    String timeSet =
        SharedHandler.getSharedPref(SharedHandler.timeNotificationKey) == false
            ? ""
            : SharedHandler.getSharedPref(SharedHandler.timeNotificationKey);

    DateTime? scheduledDate = timeSet == "" ? null : DateTime.parse(timeSet);
    createNotification(
        title: currentWeather.currentCountryDetails!.currentCity +
            Emojis.wheater_thermometer +
            Emojis.sky_cloud_with_snow,
        body:
            '${currentWeather.weatherOfDaysList[0].currentTemp}°C/${currentWeather.weatherOfDaysList[0].feelsLikeTemp}°C . ${currentWeather.weatherOfDaysList[0].weatherStatus}',
        bigPicture:
            "https://www.vietnamonline.com/media/cache/7e/e6/7ee69ffc1c68e13fe33645f21434984a.jpg",
        schedule: scheduledDate == null
            ? null
            : NotificationCalendar(
                hour: scheduledDate.hour,
                minute: scheduledDate.minute,
                second: scheduledDate.second,
                repeats: true,
              ));
  }
  

  _initNotification() async {
    
    debugPrint('initNotification');
    initWeatherNotification();  
    }

  _locationListener() async {
    late StreamSubscription streamSubscription;
    Stream stream = Geolocator.getServiceStatusStream();
    streamSubscription = stream.listen((event) async {
      //emit loading state while getting the permission or the position
      emit(LoadingSettingLocationState());
      if (event == ServiceStatus.enabled) {
        await initServices();
      } else {
        emit(LocationServicesDisabledState());
      }
      //To close the stream
      streamSubscription.cancel();
    });
  }

  openLocationSettingsAndRetry() async {
    bool isLocationOpened = await LocationAPI.isLocationServiceEnabled();
    await _locationListener();
    if (!isLocationOpened) {
      await LocationAPI.openLocationSettings();
    }
  }

  Future<void> _getWeatherApiData() async {
    emit(LoadingDataFromWeatherAPIState());
    try {
      var lat = positionOfUser!.latitude;
      var lon = positionOfUser!.longitude;
      currentWeather = await WeatherAPI.getWeatherData(lat: lat, lon: lon);
      windIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.windSpeed))
          .toList();
      humidityIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.humidity))
          .toList();
      sliverTitle = currentWeather.currentCountryDetails!.currentCity;
      // uvIndexes = await UVAPI.getUVData(lat: lat, lon: lon);
      uvIndexes = await UVAPI.getUVData();
      emit(SuccessfullyLoadedDataFromWeatherAPIState());
    } catch (e) {
      debugPrint("GetWeatherAPI:$e");
      emit(FailedToLoadDataFromWeatherAPIState());
      rethrow;
    }
  }

  getSavedLocations() {
    return SharedHandler.getListFromSharedPref(
      SharedHandler.favoriteLocationsListKey,
    );
  }

  getSavedTemps() {
    return SharedHandler.getListFromSharedPref(
        SharedHandler.favoriteLocationsTempListKey);
  }

  Future<void> getWeather(double lat, double lon) async {
    emit(LoadingDataFromWeatherAPIState());
    try {
      currentWeather = await WeatherAPI.getWeatherData(lat: lat, lon: lon);
      windIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.windSpeed))
          .toList();
      humidityIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.humidity))
          .toList();
      sliverTitle = currentWeather.currentCountryDetails!.currentCity;
      // uvIndexes = await UVAPI.getUVData(lat: lat, lon: lon);
      uvIndexes = await UVAPI.getUVData();
      emit(SuccessfullyLoadedDataFromWeatherAPIState());
    } catch (e) {
      debugPrint("GetWeatherAPI:$e");
      emit(FailedToLoadDataFromWeatherAPIState());
      rethrow;
    }
  }

  Future<void> getWeatherByCityName(String cityName) async {
    emit(LoadingDataFromWeatherAPIState());
    try {
      currentWeather = await WeatherAPI.getWeatherDataByCityName(cityName: cityName);
      windIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.windSpeed))
          .toList();
      humidityIndexes = currentWeather.weatherOfDaysList
          .map((e) => convertNumber<double>(e.humidity))
          .toList();
      sliverTitle = currentWeather.currentCountryDetails!.currentCity;
      // uvIndexes = await UVAPI.getUVData(lat: lat, lon: lon);
      uvIndexes = await UVAPI.getUVData();
      emit(SuccessfullyLoadedDataFromWeatherAPIState());
    } catch (e) {
      debugPrint("GetWeatherAPI:$e");
      emit(FailedToLoadDataFromWeatherAPIState());
      rethrow;
    }
  }
}
