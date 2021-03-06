#' transxchange2gtfs
#'
#' @param obj transxchange object
#' @param run_debug logical, should debugs be done?
#' @param cal calendar
#' @param naptan naptan
#' @param quiet logical should messages be displayed
#' @param scotland logical should Scottish bank holidays be used?
#'
#' @noRd
#'
transxchange_export <- function(obj, run_debug = TRUE,
                                cal = get_bank_holidays(),
                                naptan = get_naptan(),
                                quiet = TRUE, scotland = FALSE) {
  JourneyPatternSections <- obj[["JourneyPatternSections"]]
  Operators <- obj[["Operators"]]
  Routes <- obj[["Routes"]]
  # RouteSections           <-  obj[["RouteSections"]]
  Services_main <- obj[["Services_main"]]
  StandardService <- obj[["StandardService"]]
  # Services_NonOperation   <-  obj[["Services_NonOperation"]]
  StopPoints <- obj[["StopPoints"]]
  VehicleJourneys <- obj[["VehicleJourneys"]]
  VehicleJourneys_exclude <- obj[["DaysOfNonOperation"]]
  VehicleJourneys_include <- obj[["DaysOfOperation"]]
  SpecialDaysOperation <- obj[["SpecialDaysOperation"]]
  VehicleJourneys_notes <- obj[["VehicleJourneys_notes"]]
  # VehicleJourneysTimingLinks <- obj[["VehicleJourneysTimingLinks"]]
  ServicedOrganisations <- obj[["ServicedOrganisations"]]

  # select holidays to use
  if (scotland) {
    cal <- cal[cal$Scotland, ]
  } else {
    cal <- cal[cal$EnglandWales, ]
  }

  # Swtich NA to NULL
  if (length(VehicleJourneys_exclude) == 1) {
    if (is.na(VehicleJourneys_exclude)) {
      VehicleJourneys_exclude <- NULL
    }
  }

  if (length(VehicleJourneys_include) == 1) {
    if (is.na(VehicleJourneys_include)) {
      VehicleJourneys_include <- NULL
    }
  }


  # Early Subsets - move to import code
  VehicleJourneys <- VehicleJourneys[, c(
    "VehicleJourneyCode", "ServiceRef", "JourneyPatternRef", "DepartureTime", "DaysOfWeek",
    "BankHolidaysOperate", "BankHolidaysNoOperate", "ServicedDaysOfOperation", "ServicedDaysOfNonOperation"
  )]
  if (anyNA(VehicleJourneys$JourneyPatternRef)) {
    warning(paste0("missing JourneyPatternRefs are excluded in ", Services_main$ServiceCode))
  }
  VehicleJourneys <- VehicleJourneys[!is.na(VehicleJourneys$JourneyPatternRef), ]
  Services_main$StartDate <- as.Date(Services_main$StartDate)
  Services_main$EndDate <- as.Date(Services_main$EndDate)

  # Remove Bookeable Services
  if (class(VehicleJourneys_notes) == "data.frame") {
    VehicleJourneys_notes <- VehicleJourneys_notes[grepl("book", VehicleJourneys_notes$NoteText), ]
    vjc_remove <- unique(VehicleJourneys_notes$VehicleJourneyCode)
    VehicleJourneys <- VehicleJourneys[!VehicleJourneys$VehicleJourneyCode %in% vjc_remove, ]
    if (nrow(VehicleJourneys) == 0) {
      return(NULL)
    }
  }



  # Split Service Organisations
  if (class(ServicedOrganisations) == "data.frame") {
    vj_so <- VehicleJourneys[, c("VehicleJourneyCode", "ServicedDaysOfOperation", "ServicedDaysOfNonOperation")]

    ServicedOrganisations_workdays <- ServicedOrganisations[, c("OrganisationCode", "WorkingDays.StartDate", "WorkingDays.EndDate")]
    ServicedOrganisations_holidays <- ServicedOrganisations[, c("OrganisationCode", "Holidays.StartDate", "Holidays.EndDate", "Holidays.Description")]
    ServicedOrganisations_workdays <- ServicedOrganisations_workdays[!is.na(ServicedOrganisations_workdays$WorkingDays.StartDate), ]
    ServicedOrganisations_holidays <- ServicedOrganisations_holidays[!is.na(ServicedOrganisations_holidays$Holidays.StartDate), ]
    if (nrow(ServicedOrganisations_workdays) == 0) {
      ServicedOrganisations_workdays <- NULL
    } else {
      vj_so_do <- vj_so[, c("VehicleJourneyCode", "ServicedDaysOfOperation")]
      vj_so_do <- vj_so_do[!is.na(vj_so_do$ServicedDaysOfOperation), ]
      if (nrow(vj_so_do) > 0) {
        ServicedOrganisations_workdays <- dplyr::left_join(ServicedOrganisations_workdays,
          vj_so_do,
          by = c("OrganisationCode" = "ServicedDaysOfOperation")
        )
        ServicedOrganisations_workdays <- ServicedOrganisations_workdays[, c("VehicleJourneyCode", "WorkingDays.StartDate", "WorkingDays.EndDate")]
        names(ServicedOrganisations_workdays) <- c("VehicleJourneyCode", "StartDate", "EndDate")
      } else {
        ServicedOrganisations_workdays <- NULL
        # stop("check this, service that runs only during holidays?")
      }
    }

    if (nrow(ServicedOrganisations_holidays) == 0) {
      ServicedOrganisations_holidays <- NULL
    } else {
      vj_so_no <- vj_so[, c("VehicleJourneyCode", "ServicedDaysOfNonOperation")]
      vj_so_no <- vj_so_no[!is.na(vj_so_no$ServicedDaysOfNonOperation), ]
      if (nrow(vj_so_no) > 0) {
        ServicedOrganisations_holidays <- dplyr::left_join(ServicedOrganisations_holidays,
          vj_so_no,
          by = c("OrganisationCode" = "ServicedDaysOfNonOperation")
        )
        ServicedOrganisations_holidays <- ServicedOrganisations_holidays[, c("VehicleJourneyCode", "Holidays.StartDate", "Holidays.EndDate")]
        names(ServicedOrganisations_holidays) <- c("VehicleJourneyCode", "StartDate", "EndDate")
        if (all(is.na(ServicedOrganisations_holidays$VehicleJourneyCode))) {
          ServicedOrganisations_holidays <- NULL
        }
      } else {
        ServicedOrganisations_holidays <- NULL
        # stop("check this, service that runs only during holidays?")
      }
    }
  } else {
    ServicedOrganisations_workdays <- NULL
    ServicedOrganisations_holidays <- NULL
  }



  # Append ServicedOrganisations Dates to inclusions and exclusions
  # If VehicleJourneys_exclude or _include have ServicedOrganisationRef rather than Start and End Dates
  if (!is.null(VehicleJourneys_exclude)) {
    if (!all(names(VehicleJourneys_exclude) %in% c("VehicleJourneyCode", "StartDate", "EndDate"))) {
      stop("need to rebuild this case for new ServicedOrganisations")
    }
  }

  if (!is.null(VehicleJourneys_include)) {
    if (!all(names(VehicleJourneys_include) %in% c("VehicleJourneyCode", "StartDate", "EndDate"))) {
      stop(stop("need to rebuild this case for new ServicedOrganisations"))
    }
  }


  # Import ServicedOrganisations in to VehicleJourneys
  VehicleJourneys_exclude <- rbind(VehicleJourneys_exclude, ServicedOrganisations_holidays)
  VehicleJourneys_include <- rbind(VehicleJourneys_include, ServicedOrganisations_workdays)




  # Journey Pattern Sections ------------------------------------------------

  if (run_debug) {
    chk <- gsub("[0-9]", "", JourneyPatternSections$RunTime)
    chk <- unique(chk)
    chk_valid <- c("PTM", "PTS", "PTMS", "PTHM", "PTH", "PTHMS","PTHS")
    if (!all(chk %in% chk_valid)) {
      stop(paste0("Unknown time formats: ", chk[!chk %in% chk_valid]))
    }
    rm(chk, chk_valid)
  }

  JourneyPatternSections$RunTime <- clean_times(JourneyPatternSections$RunTime)
  JourneyPatternSections$To.WaitTime <- clean_times(JourneyPatternSections$To.WaitTime)


  # stops -------------------------------------------------------------------

  stops <- StopPoints[, "StopPointRef", drop = FALSE]
  names(stops) <- c("stop_id")
  stops$stop_id <- as.character(stops$stop_id)
  stops <- dplyr::left_join(stops, naptan, by = "stop_id")


  # routes ------------------------------------------------------------------
  # route_id, agency_id, route_short_name, route_long_name, route_desc, route_type

  routes <- Services_main[c("ServiceCode", "RegisteredOperatorRef", "LineName", "Description", "Mode", "Origin", "Destination")]
  routes$route_long_name <- paste0(routes$Origin, " - ", routes$Destination)
  names(routes) <- c("route_id", "agency_id", "route_short_name", "route_desc", "route_type", "Origin", "Destination", "route_long_name")
  routes <- routes[, c("route_id", "agency_id", "route_short_name", "route_long_name", "route_desc", "route_type")]
  routes$agency_id <- gsub("OId_", "", routes$agency_id)
  routes$route_type <- sapply(routes$route_type, clean_route_type)

  # Shorten route_short_name
  routes$route_short_name <- gsub("Park & Ride", "P&R", routes$route_short_name)
  routes$route_short_name <- gsub("Road", "Rd", routes$route_short_name)
  routes$route_short_name <- gsub("Connecting Communities ", "", routes$route_short_name)
  routes$route_short_name <- gsub("|the busway", "", routes$route_short_name)
  routes$route_short_name <- ifelse(nchar(routes$route_short_name) > 6, gsub(" ", "", routes$route_short_name), routes$route_short_name)
  routes$route_short_name[nchar(routes$route_short_name) > 6] <- "" # Remove long names to pass validation check

  # Remove Duplicated descriptions
  routes$route_desc <- ifelse(routes$route_desc == routes$route_long_name, "", routes$route_desc)


  # agency ------------------------------------------------------------------
  # agency_id, agency_name, agency_url, agency_timezone

  # Check which code is used
  if (all(routes$agency_id %in% Operators$NationalOperatorCode)) {
    agency_id <- Operators$NationalOperatorCode
  } else if (all(routes$agency_id %in% Operators$OperatorCode)) {
    agency_id <- Operators$OperatorCode
  } else {
    if (length(unique(routes$agency_id)) == 1 & length(unique(Operators$NationalOperatorCode)) == 1) {
      agency_id <- unique(routes$agency_id)
    } else {
      stop("Unable to match OperatorCode between Services_main and Operators")
    }
  }

  if (is.null(Operators$TradingName)) {
    agency_name <- Operators$OperatorShortName
  } else {
    if (is.na(Operators$TradingName)) {
      agency_name <- Operators$OperatorShortName
    } else {
      agency_name <- Operators$TradingName
    }
  }


  agency <- data.frame(
    agency_id = agency_id,
    agency_name = agency_name,
    agency_url = "http://www.URL-IS-MISSING.com",
    agency_timezone = "Europe/London",
    agency_lang = "en",
    stringsAsFactors = FALSE
  )

  name2id <- function(nm){
    aid <- strsplit(as.character(nm), " ")[[1]]
    aid <- lapply(aid, function(x){
      xchar <- nchar(x)
      if(xchar >= 4){
        x <- paste0(substr(x,1,3), substr(x,xchar,xchar))
      }
      return(x)
    })
    aid <- unlist(aid)
    aid <- paste0(aid, collapse = "")
    return(aid)
  }


  for (j in seq(1, nrow(agency))) {
    if (agency$agency_id[j] == "O1") {
      aid <- name2id(agency$agency_name[j])
      agency$agency_id[j] <- aid
      routes$agency_id[routes$agency_id == "O1"] <- aid
      warning(paste0("Agency ID is O1 changing to ", aid))
    }
  }




  # trips calendar calendar_dates -------------------------------------------------
  ###### Redo: Again
  trips <- VehicleJourneys[, c("ServiceRef", "VehicleJourneyCode", "DepartureTime", "JourneyPatternRef", "DaysOfWeek")]
  names(trips) <- c("route_id", "trip_id", "DepartureTime", "JourneyPatternRef", "DaysOfWeek")
  trips[] <- lapply(trips, as.character)


  trips$StartDate <- unique(Services_main$StartDate) # unique is bodge to add in support for mulitple services
  trips$EndDate <- unique(Services_main$EndDate)
  # trips$service_id_temp <- seq(1,nrow(trips))
  trips$trip_id <- as.character(trips$trip_id)

  # If DaysOfWeek unspecidied for vehicle jounrey inherit from Services_main
  trips$DaysOfWeek[is.na(trips$DaysOfWeek)] <- Services_main$DaysOfWeek


  # Step 1: Do we Have any exclusions
  if (class(VehicleJourneys_exclude) == "data.frame") {
    # Yes - Build Exclusions
    # Split Exclusions by Vehicle Jounrey
    trip_exc <- split(VehicleJourneys_exclude, VehicleJourneys_exclude$VehicleJourneyCode)
    trip_split <- split(trips, trips$trip_id)
    trip_split <- lapply(trip_split, exclude_trips, trip_exc = trip_exc)
    trips <- dplyr::bind_rows(trip_split)
    trips_exclude <- trips[, c("trip_id", "exclude_days")]
    trips_exclude <- trips_exclude[lengths(trips_exclude$exclude_days) > 0, ] # For lists
    trips_exclude <- trips_exclude[!is.na(trips_exclude$exclude_days), ] # For NAs
    if (nrow(trips_exclude) > 0) {
      trips_exclude <- data.frame(
        trip_id = rep(trips_exclude$trip_id, times = lengths(trips_exclude$exclude_days)),
        date = as.Date(unlist(trips_exclude$exclude_days), origin = "1970-01-01"),
        stringsAsFactors = FALSE
      )
      trips_exclude$exception_type <- 2
    } else {
      rm(trips_exclude)
    }
  }

  # Step 1b: Do we have any Inclusions
  if (class(VehicleJourneys_include) == "data.frame") {
    trips_include <- split(VehicleJourneys_include, VehicleJourneys_include$VehicleJourneyCode)
    trips_include <- lapply(trips_include, list_include_days)
    trips_include <- data.frame(
      trip_id = rep(names(trips_include), times = lengths(trips_include)),
      date = as.Date(unlist(trips_include), origin = "1970-01-01"),
      stringsAsFactors = FALSE
    )
    trips_include$exception_type <- 1
  }


  # Step 2: Prep the Bank Holidays
  cal <- cal[cal$date >= Services_main$StartDate & cal$date <= Services_main$EndDate, ]
  bank_holidays <- VehicleJourneys[, c("VehicleJourneyCode", "BankHolidaysOperate", "BankHolidaysNoOperate")]
  # bank_holidays <- bank_holidays[(!is.na(bank_holidays$BankHolidaysOperate)) | (!is.na(bank_holidays$BankHolidaysNoOperate)),]
  # if(nrow(bank_holidays) > 0){
  #
  # }
  bank_holidays[] <- lapply(bank_holidays, as.character)
  bank_holidays <- unique(bank_holidays)
  names(bank_holidays) <- c("trip_id", "BankHolidaysOperate", "BankHolidaysNoOperate")
  bank_holidays$BankHolidaysOperate[bank_holidays$BankHolidaysOperate == "AllBankHolidays"] <- paste(cal$name, collapse = " ")
  bank_holidays$BankHolidaysNoOperate[bank_holidays$BankHolidaysNoOperate == "AllBankHolidays"] <- paste(cal$name, collapse = " ")

  bank_holidays_inc <- break_up_holidays2(bank_holidays, "BankHolidaysOperate")
  bank_holidays_exc <- break_up_holidays2(bank_holidays, "BankHolidaysNoOperate")
  if (!is.null(bank_holidays_inc)) {
    bank_holidays_inc <- dplyr::left_join(bank_holidays_inc, cal, by = c("hols" = "name"))
  }
  if (!is.null(bank_holidays_exc)) {
    bank_holidays_exc <- dplyr::left_join(bank_holidays_exc, cal, by = c("hols" = "name"))
  }
  bank_holidays <- rbind(bank_holidays_inc, bank_holidays_exc)
  bank_holidays <- bank_holidays[, c("trip_id", "date", "exception_type")]

  bank_holidays <- bank_holidays[!is.na(bank_holidays$date), ]


  # Step 3: Merge Exclusions and bank_holidays, then summarise the exclusions
  if (exists("trips_exclude")) {
    calendar_dates <- trips_exclude
    if (nrow(bank_holidays) > 0) {
      calendar_dates <- rbind(calendar_dates, bank_holidays)
    }
  } else {
    calendar_dates <- bank_holidays
  }

  if (exists("trips_include")) {
    calendar_dates <- rbind(calendar_dates, trips_include)
  }

  if (nrow(calendar_dates) == 0) {
    calendar_dates <- NULL
  }

  # Step 4: Make the calendar
  calendar <- trips[, c("trip_id", "StartDate", "EndDate", "DaysOfWeek")]
  names(calendar) <- c("trip_id", "start_date", "end_date", "DaysOfWeek")
  calendar$start_date <- gsub("-", "", calendar$start_date)
  calendar$end_date <- gsub("-", "", calendar$end_date)

  # Step 5: Make the unique service_id
  if (is.null(calendar_dates)) {
    calendar_dates <- data.frame(
      trip_id = character(),
      date = character(),
      exception_type = character(),
      stringsAsFactors = FALSE
    )
    calendar_summary <- dplyr::group_by(calendar, start_date, end_date, DaysOfWeek)
  } else {
    # remove calendar_dates for trips that have been competly removed
    calendar_dates <- calendar_dates[calendar_dates$trip_id %in% calendar$trip_id, ]

    calendar_summary <- dplyr::group_by(calendar, start_date, end_date, DaysOfWeek)
    calendar_dates_summary <- dplyr::group_by(calendar_dates, trip_id)
    calendar_dates_summary <- dplyr::summarise(calendar_dates_summary,
      pattern = paste(c(date, exception_type), collapse = "")
    )
    calendar_summary$trip_id <- as.character(calendar_summary$trip_id)
    calendar_summary <- dplyr::left_join(calendar, calendar_dates_summary, by = "trip_id")
    calendar_summary <- dplyr::group_by(calendar_summary, start_date, end_date, DaysOfWeek, pattern)
  }

  calendar_summary$service_id <- dplyr::group_indices(calendar_summary)
  calendar_summary <- calendar_summary[, c("trip_id", "service_id")]
  calendar <- dplyr::left_join(calendar, calendar_summary, by = "trip_id")
  calendar_dates <- dplyr::left_join(calendar_dates, calendar_summary, by = "trip_id")
  trips <- dplyr::left_join(trips, calendar_summary, by = "trip_id")

  calendar <- calendar[, c("service_id", "start_date", "end_date", "DaysOfWeek")]
  calendar <- unique(calendar)

  calendar_dates <- calendar_dates[, c("service_id", "date", "exception_type")]

  # Check SpecialDaysOperation
  if (!is.null(SpecialDaysOperation)) {
    # stop("check against new method ")
    SpecialDaysOperation$exception_type <- ifelse(SpecialDaysOperation$type == "DaysOperation", 1, 2)
    # service_ids <- unique(calendar_dates$service_id)
    service_ids <- unique(calendar$service_id)
    SpecialDaysOperation <- data.frame(
      service_id = rep(service_ids, nrow(SpecialDaysOperation)),
      date = rep(SpecialDaysOperation$StartDate, length(service_ids)),
      exception_type = rep(SpecialDaysOperation$exception_type, length(service_ids)),
      stringsAsFactors = FALSE
    )
    calendar_dates <- rbind(calendar_dates, SpecialDaysOperation)
  }

  calendar_dates <- unique(calendar_dates)
  calendar_dates$date <- gsub("-", "", calendar_dates$date)

  if (run_debug) {
    if (any(is.na(calendar_dates))) {
      stop("NA values in calendar_dates")
    }
  }

  trips <- trips[, c("route_id", "service_id", "trip_id", "DepartureTime", "JourneyPatternRef")]

  if (nrow(trips) == 0) {
    # In some cases there are no trips e.g. a total exclusion of all dates
    # so return nothing
    return(NULL)
  }

  # Step 6: Make calendar DaysOfWeek of the week
  calendar_days <- as.data.frame(t(sapply(as.character(calendar$DaysOfWeek), clean_days, USE.NAMES = FALSE)))
  names(calendar_days) <- c("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")

  calendar <- cbind(calendar, calendar_days)
  calendar <- calendar[, c("service_id", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday", "start_date", "end_date")]
  rm(calendar_days)

  # Step 7: Make stop_times

  stop_times <- make_stop_times(jps = JourneyPatternSections, trips = trips, ss = StandardService)
  # stop_times <- check_stop_times(stop_times)

  # rebuild ids
  # trips$service_id <- gsub("[[:punct:]]","",trips$service_id)
  trips$trip_id <- gsub("[[:punct:]]", "", trips$trip_id)
  trips$route_id <- gsub("[[:punct:]]", "", trips$route_id)
  trips <- trips[, c("route_id", "service_id", "trip_id")]

  routes$route_id <- gsub("[[:punct:]]", "", routes$route_id)
  stop_times$trip_id <- gsub("[[:punct:]]", "", stop_times$trip_id)

  # Clean Up any flaws

  # remove unused stops
  stops <- stops[stops$stop_id %in% unique(stop_times$stop_id), ]

  res_final <- list(agency, stops, routes, trips, stop_times, calendar, calendar_dates)
  names(res_final) <- c("agency", "stops", "routes", "trips", "stop_times", "calendar", "calendar_dates")

  gtfs_validate_internal(res_final)

  return(res_final)
}
