library google_places_flutter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:google_places_flutter/model/place_details.dart';
import 'package:google_places_flutter/model/place_type.dart';
import 'package:google_places_flutter/model/prediction.dart';

import 'package:dio/dio.dart';
import 'package:rxdart/rxdart.dart';

import 'DioErrorHandler.dart';

// ignore: must_be_immutable
class GooglePlaceAutoCompleteTextField extends StatefulWidget {
  InputDecoration inputDecoration;
  ItemClick? itemClick;
  GetPlaceDetailswWithLatLng? getPlaceDetailWithLatLng;
  bool isLatLngRequired = true;

  TextStyle textStyle;
  String googleAPIKey;
  int debounceTime = 600;
  List<String>? countries = [];
  TextEditingController textEditingController = TextEditingController();
  ListItemBuilder? itemBuilder;
  Widget? seperatedBuilder;
  void clearData;
  BoxDecoration? boxDecoration;
  bool isCrossBtnShown;
  bool showError;
  double? containerHorizontalPadding;
  double? containerVerticalPadding;
  FocusNode? focusNode;
  PlaceType? placeType;
  String? language;
  TextInputAction? textInputAction;
  final VoidCallback? formSubmitCallback;
  TextInputType? keyboardType;

  final String? Function(String?, BuildContext)? validator;

  final double? latitude;
  final double? longitude;

  /// This is expressed in **meters**
  final int? radius;
  final Function? onChanged;
  final Function? onPressedLatLng;
  final Function? onPressedClose;

  GooglePlaceAutoCompleteTextField(
      {required this.textEditingController,
      required this.googleAPIKey,
      this.debounceTime = 600,
      this.inputDecoration = const InputDecoration(),
      this.itemClick,
      this.isLatLngRequired = true,
      this.textStyle = const TextStyle(),
      this.countries,
      this.getPlaceDetailWithLatLng,
      this.itemBuilder,
      this.boxDecoration,
      this.isCrossBtnShown = true,
      this.seperatedBuilder,
      this.showError = true,
      this.containerHorizontalPadding,
      this.containerVerticalPadding,
      this.focusNode,
      this.placeType,
      this.language = 'en',
      this.validator,
      this.latitude,
      this.longitude,
      this.radius,
      this.formSubmitCallback,
      this.textInputAction,
      this.keyboardType,
      this.clearData,
      this.onChanged,
      this.onPressedLatLng,
      this.onPressedClose});

  @override
  _GooglePlaceAutoCompleteTextFieldState createState() =>
      _GooglePlaceAutoCompleteTextFieldState();
}

class _GooglePlaceAutoCompleteTextFieldState
    extends State<GooglePlaceAutoCompleteTextField> {
  final subject = new PublishSubject<String>();
  OverlayEntry? _overlayEntry;
  List<Prediction> alPredictions = [];

  TextEditingController controller = TextEditingController();
  final LayerLink _layerLink = LayerLink();
  bool isSearched = false;

  bool isCrossBtn = true;
  late var _dio;

  CancelToken? _cancelToken = CancelToken();

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: Container(
        padding: EdgeInsets.symmetric(
            horizontal: widget.containerHorizontalPadding ?? 0,
            vertical: widget.containerVerticalPadding ?? 0),
        alignment: Alignment.centerLeft,
        decoration: widget.boxDecoration ??
            BoxDecoration(
                shape: BoxShape.rectangle,
                border: Border.all(color: Colors.grey, width: 0.6),
                borderRadius: BorderRadius.all(Radius.circular(10))),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextFormField(
                decoration: widget.inputDecoration ?? defaultInputDecoration(),
                style: widget.textStyle,
                controller: widget.textEditingController,
                focusNode: widget.focusNode ?? FocusNode(),
                keyboardType:
                    widget.keyboardType ?? TextInputType.streetAddress,
                textInputAction: widget.textInputAction ?? TextInputAction.done,
                onFieldSubmitted: (value) {
                  if (widget.formSubmitCallback != null) {
                    widget.formSubmitCallback!();
                  }
                },
                validator: (inputString) {
                  return widget.validator?.call(inputString, context);
                },
                onChanged: (string) {
                  subject.add(string);
                  widget.onChanged?.call(string);
                  if (widget.isCrossBtnShown) {
                    isCrossBtn = string.isNotEmpty ? true : false;
                    setState(() {});
                  }
                },
              ),
            ),
            (!widget.isCrossBtnShown)
                ? SizedBox()
                : isCrossBtn && _showCrossIconWidget()
                    ? IconButton(onPressed: clearData, icon: Icon(Icons.close))
                    : SizedBox()
          ],
        ),
      ),
    );
  }

  getLocation(String text) async {
    String apiURL =
        "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$text&key=${widget.googleAPIKey}&language=${widget.language}";

    if (widget.countries != null) {
      // in

      for (int i = 0; i < widget.countries!.length; i++) {
        String country = widget.countries![i];

        if (i == 0) {
          apiURL = apiURL + "&components=country:$country";
        } else {
          apiURL = apiURL + "|" + "country:" + country;
        }
      }
    }
    if (widget.placeType != null) {
      apiURL += "&types=${widget.placeType?.apiString}";
    }

    if (widget.latitude != null &&
        widget.longitude != null &&
        widget.radius != null) {
      apiURL = apiURL +
          "&location=${widget.latitude},${widget.longitude}&radius=${widget.radius}";
    }

    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
      _cancelToken = CancelToken();
    }

    // print("urlll $apiURL");
    try {
      String proxyURL = "https://cors-anywhere.herokuapp.com/";
      String url = kIsWeb ? proxyURL + apiURL : apiURL;

      Response response = await _dio.get(url);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      Map map = response.data;
      if (map.containsKey("error_message")) {
        throw response.data;
      }

      PlacesAutocompleteResponse subscriptionResponse =
          PlacesAutocompleteResponse.fromJson(response.data);

      if (text.length == 0) {
        alPredictions.clear();
        this._overlayEntry!.remove();
        return;
      }

      isSearched = false;
      alPredictions.clear();
      if (subscriptionResponse.predictions!.length > 0 &&
          (widget.textEditingController.text.toString().trim()).isNotEmpty) {
        alPredictions.addAll(subscriptionResponse.predictions!);
      }

      this._overlayEntry = null;
      this._overlayEntry = this._createOverlayEntry();
      Overlay.of(context).insert(this._overlayEntry!);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  @override
  void initState() {
    super.initState();
    _dio = Dio();
    subject.stream
        .distinct()
        .debounceTime(Duration(milliseconds: widget.debounceTime))
        .listen(textChanged);
  }

  textChanged(String text) async {
    if (text.isNotEmpty) {
      getLocation(text);
    } else {
      alPredictions.clear();
      this._overlayEntry!.remove();
    }
  }

  OverlayEntry? _createOverlayEntry() {
    if (context.findRenderObject() != null) {
      RenderBox renderBox = context.findRenderObject() as RenderBox;
      var size = renderBox.size;
      var offset = renderBox.localToGlobal(Offset.zero);
      return widget.textEditingController.text.isEmpty
          ? OverlayEntry(builder: (_) => const SizedBox())
          : OverlayEntry(
              builder: (context) => Positioned(
                    left: offset.dx,
                    top: size.height + offset.dy,
                    width: size.width,
                    child: CompositedTransformFollower(
                      showWhenUnlinked: false,
                      link: this._layerLink,
                      offset: Offset(0.0, size.height + 5.0),
                      child: Material(
                          child: ListView.separated(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: alPredictions.length,
                        separatorBuilder: (context, pos) =>
                            widget.seperatedBuilder ?? SizedBox(),
                        itemBuilder: (BuildContext context, int index) {
                          return InkWell(
                            onTap: () async {
                              var selectedData = alPredictions[index];
                              if (index < alPredictions.length) {
                                widget.itemClick!(selectedData);

                                if (widget.isLatLngRequired) {
                                  await getPlaceDetailsFromPlaceId(
                                      selectedData);
                                }
                                removeOverlay();
                              }
                            },
                            child: widget.itemBuilder != null
                                ? widget.itemBuilder!(
                                    context, index, alPredictions[index])
                                : Container(
                                    padding: EdgeInsets.all(10),
                                    child: Text(
                                        alPredictions[index].description!)),
                          );
                        },
                      )),
                    ),
                  ));
    }
    return null;
  }

  removeOverlay() {
    alPredictions.clear();
    this._overlayEntry = this._createOverlayEntry();

    Overlay.of(context).insert(this._overlayEntry!);
    this._overlayEntry!.markNeedsBuild();
  }

  Future<void> getPlaceDetailsFromPlaceId(Prediction prediction) async {
    //String key = GlobalConfiguration().getString('google_maps_key');

    var url =
        "https://maps.googleapis.com/maps/api/place/details/json?placeid=${prediction.placeId}&key=${widget.googleAPIKey}";
    try {
      Response response = await _dio.get(
        url,
      );

      PlaceDetails placeDetails = PlaceDetails.fromJson(response.data);

      prediction.lat = placeDetails.result!.geometry!.location!.lat.toString();
      prediction.lng = placeDetails.result!.geometry!.location!.lng.toString();

      //
      prediction.placeDetailJson = response.data;

      widget.getPlaceDetailWithLatLng!(prediction);
    } catch (e) {
      var errorHandler = ErrorHandler.internal().handleError(e);
      _showSnackBar("${errorHandler.message}");
    }
  }

  void clearData() {
    widget.textEditingController.clear();
    if (_cancelToken?.isCancelled == false) {
      _cancelToken?.cancel();
    }

    setState(() {
      alPredictions.clear();
      isCrossBtn = false;
    });

    if (this._overlayEntry != null) {
      try {
        this._overlayEntry?.remove();
      } catch (e) {}
    }
  }

  _showCrossIconWidget() {
    return (widget.textEditingController.text.isNotEmpty);
  }

  _showSnackBar(String errorData) {
    if (widget.showError) {
      final snackBar = SnackBar(
        content: Text("$errorData"),
      );

      // Find the ScaffoldMessenger in the widget tree
      // and use it to show a SnackBar.
      ScaffoldMessenger.of(context).showSnackBar(snackBar);
    }
  }

  InputDecoration defaultInputDecoration() {
    return InputDecoration(
      filled: true,
      fillColor: AppColors.greyTextField,
      hintText: 'Search...',
      hintStyle: AppTextStyle.normalStyle.copyWith(
        fontWeight: FontWeight.normal,
        color: AppColors.greyHintText,
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.greyTextField),
      ),
      contentPadding: const EdgeInsets.only(right: Dimens.PADDING_LARGE),
      prefixIconConstraints: const BoxConstraints(
        minHeight: Dimens.IC_CLOSE_APPBAR,
        minWidth: Dimens.IC_CLOSE_APPBAR,
      ),
      prefixIcon: Padding(
        padding: const EdgeInsets.all(Dimens.PADDING_SMALL),
        child: SvgPicture.asset(Images.icSearch),
      ),
      suffixIconConstraints: const BoxConstraints(
        minHeight: Dimens.IC_CLOSE_APPBAR,
        minWidth: Dimens.IC_CLOSE_APPBAR,
      ),
      suffixIcon: widget.textEditingController.text.isEmpty
          ? GestureDetector(
              onTap: () => widget.onPressedLatLng?.call(),
              child: Padding(
                padding: const EdgeInsets.all(Dimens.PADDING_SMALL),
                child: SvgPicture.asset(
                  Images.icLocationSetting,
                  colorFilter: ColorFilter.mode(
                    AppColors.greyCloseIcon,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            )
          : GestureDetector(
              onTap: () {
                widget.onPressedClose?.call();
                clearData();
              },
              child: Padding(
                padding: const EdgeInsets.all(Dimens.PADDING_SMALL),
                child: SvgPicture.asset(
                  Images.icCloseSearchBar,
                  colorFilter: ColorFilter.mode(
                    AppColors.greyCloseIcon,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.greyTextField),
      ),
    );
  }
}

class AppTextStyle {
  AppTextStyle._();

  static TextStyle normalStyle = const TextStyle(
      fontWeight: FontWeight.w400,
      color: AppColors.blueText,
      fontSize: Dimens.TEXT_SIZE_NORMAL);
}

class Images {
  Images._();

  static const String iconPath = 'lib/res/icons';

  static const icCloseSearchBar = '$iconPath/ic_close_search_bar.svg';
  static const icLocationSetting = '$iconPath/ic_location_setting.svg';
  static const icSearch = '$iconPath/ic_search.svg';
}

class AppColors {
  AppColors._();

  static const greyTextField = Color(0xffF7F8FB);
  static const greyCloseIcon = Color(0xff7B7C81);
  static const greyHintText = Color(0xff9FA5B0);
  static const blueText = Color(0xff3D4257);
}

class Dimens {
  Dimens._();

  static const PADDING_SMALL = 10.0;
  static const IC_CLOSE_APPBAR = 16.0;
  static const PADDING_LARGE = 20.0;
  static const TEXT_SIZE_NORMAL = 15.0;
}

PlacesAutocompleteResponse parseResponse(Map responseBody) {
  return PlacesAutocompleteResponse.fromJson(
      responseBody as Map<String, dynamic>);
}

PlaceDetails parsePlaceDetailMap(Map responseBody) {
  return PlaceDetails.fromJson(responseBody as Map<String, dynamic>);
}

typedef ItemClick = void Function(Prediction postalCodeResponse);
typedef GetPlaceDetailswWithLatLng = void Function(
    Prediction postalCodeResponse);

typedef ListItemBuilder = Widget Function(
    BuildContext context, int index, Prediction prediction);
