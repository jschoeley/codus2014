# Init --------------------------------------------------------------------

library(readr) # fast txt file input

library(dplyr) # data transformation
library(tidyr) # data transformation

library(ggplot2) # the layered grammar of graphics

# colour palette for causes of death
cpal <- c("Circulatory Diseases"              = "#FF6059",
          "Cancer"                            = "#E3B135",
          "Resperatory Diseases"              = "#79C8CC",
          "Diseases of the Nervous System"    = "#FF93F2",
          "Mental Diseases"                   = "#A176DF",
          "Accidents"                         = "#FF8500",
          "Infections & Parasites"            = "#59C580",
          "Suicides"                          = "#363636",
          "Perinatal & Congenital Conditions" = "#799BCC",
          "Other"                             = "#9A9A9A")

# Read Data ---------------------------------------------------------------

# CAUSES OF DEATH | US 2014 | 2,631,171 records | fixed field text file
#
# We read in four variables...
# `sex`: the sex of the deceased
# `age_unit`: the unit the age of the deceased is given in (years, months, hours...)
# `age`: the age of the deceased in `age_unit`
# `cod_icd10`: the underlying cause of death encoded by ICD-10 classification
#
# The variable `dummy` captures all the remaining columns. This is a sad
# necessity as of `readr` 0.2.2 resulting from the new default behavior of
# `fwf_positions`: "The width of the last column will be silently extended to
# the next line break."
cod <-
  read_fwf("./data/raw/mort2014us.zip",
           col_positions = fwf_positions(start = c(69, 70, 71, 146, 150),
                                         end =   c(69, 70, 73, 149, 150),
                                         col_names = c("sex",
                                                       "age_unit",
                                                       "age",
                                                       "cod_icd10",
                                                       "dummy")),
           col_types = "ciic"
  )

# Prepare Data ------------------------------------------------------------

# icd-10 recoding to 10 categories
RecodeICD10Cod <- function (x) {
  rep("Other", length(x)) %>%
    ifelse(grepl("^[AB]", x),
           "Infections & Parasites",
           .) %>%
    ifelse(grepl("^[CD]", x),
           "Cancer",
           .) %>%
    ifelse(grepl("^F", x),
           "Mental Diseases",
           .) %>%
    ifelse(grepl("^G", x),
           "Diseases of the Nervous System",
           .) %>%
    ifelse(grepl("^I", x),
           "Circulatory Diseases",
           .) %>%
    ifelse(grepl("^J", x),
           "Resperatory Diseases",
           .) %>%
    ifelse(grepl("^[PQ]", x),
           "Perinatal & Congenital Conditions",
           .) %>%
    ifelse(grepl("(^[VW])|(^[X][012345])", x),
           "Accidents",
           .) %>%
    ifelse(grepl("(^X[67])|(^X81)|(^X82)|(^X83)|(^X84)", x),
           "Suicides",
           .)
}

# data tidying
cod %>%
  # throw away dummy variable
  select(-dummy) %>%
  mutate(
    age_years = age,
    # convert month to completed years
    age_years = ifelse(age_unit == 2, age %/% 12, age_years),
    # convert day to completed years
    age_years = ifelse(age_unit == 4, age %/% 365, age_years),
    # convert hours to completed years
    age_years = ifelse(age_unit == 5, age %/% 8760, age_years),
    # convert minute to completed years
    age_years = ifelse(age_unit == 6, age %/% 525600, age_years),
    # set NA value for age
    age_years = ifelse(age_years == 999, NA, age_years),
    # factorize sex variable
    sex = factor(sex, levels = c("M", "F"), labels = c("Male", "Female")),
    cod_icd10_recode = RecodeICD10Cod(cod_icd10)
  ) %>%
  # throw out multi-unit age variable and unit identifier
  select(-age, -age_unit) %>%
  # remove persons with unknown age
  filter(!is.na(age_years)) -> cod_tidy

# Causes of Death by Sex --------------------------------------------------

# count cases by cause of death
cod_tidy %>%
  group_by(cod_icd10_recode) %>%
  summarise(N = n()) %>%
  # sort by magnitude, high to low
  arrange(desc(N)) -> cod_aggr

# factorise cod variable with the order of factor levels corresponding
# to the prevalence of cod's in the sample
cod_tidy$cod_icd10_recode <- factor(cod_tidy$cod_icd10_recode,
                                    levels = cod_aggr$cod_icd10_recode)

# get percentages and ranks of cause of death by sex
cod_tidy %>%
  group_by(cod_icd10_recode, sex) %>%
  summarise(value = n()) %>%
  group_by(sex) %>%
  mutate(value = value/sum(value)) %>%
  spread(key = sex, value = value) %>%
  mutate(Male_rank   = rank(-Male),
         Female_rank = rank(-Female)) -> cod_aggr_sex

# slopegraph of main causes of death by sex
ggplot(cod_aggr_sex) +
  geom_segment(aes(x = -0.5, xend = 0.5, y = Female_rank, yend = Male_rank,
                   colour = cod_icd10_recode), size = 1, show.legend = FALSE) +
  geom_text(aes(x = -0.53, y = Female_rank, label = cod_icd10_recode),
            hjust = "right", size = 4) +
  geom_text(aes(x = -0.53, y = Female_rank, label = scales::percent(Female)),
            hjust = "right", size = 4, nudge_y = -0.3) +
  geom_text(aes(x = 0.53, y = Male_rank, label = cod_icd10_recode),
            hjust = "left", size = 4) +
  geom_text(aes(x = 0.53, y = Male_rank, label = scales::percent(Male)),
            hjust = "left", size = 4, nudge_y = -0.3) +
  scale_x_continuous("",
                     limits = c(-2.5, 2.5),
                     breaks = c(-1.5, 1.5),
                     labels = c("FEMALE", "MALE")) +
  scale_y_reverse("Rank", breaks = 1:10) +
  scale_colour_manual(values = cpal) +
  theme_bw() +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major = element_blank(),
        axis.ticks.x     = element_blank(),
        panel.border     = element_blank(),
        aspect.ratio     = 1.3)

ggsave(filename = "slopegraph.pdf", path = "./fig/raw/", width = 7, height = 9)

# Number of Deaths by Cause, Age, and Sex ---------------------------------

# count cases by sex, age and cause of death
cod_tidy %>%
  # i have to work around the problem that group_by silently drops group
  # combinations that don't occour in the data instead of assigning a 0 count
  # see https://github.com/hadley/dplyr/issues/341
  mutate(dummy = 1) %>%
  complete(age_years, sex, cod_icd10_recode) %>%
  group_by(age_years, sex, cod_icd10_recode) %>%
  summarise(N = sum(dummy, na.rm = TRUE)) %>%
  group_by(sex) %>%
  # make "Other" the last factor level
  mutate(cod_icd10_recode =
           factor(cod_icd10_recode,
                  levels = c(levels(cod_icd10_recode)[levels(cod_icd10_recode) != "Other"], "Other"))) %>%
  spread(key = sex, value = N) -> cod_aggr_sex_age_cod

# back-to-back area chart of the age distribution of deaths by cause and sex
ggplot(cod_aggr_sex_age_cod, aes(x = age_years, fill = cod_icd10_recode)) +
  geom_bar(aes(y = Male), width = 1, stat = "identity") +
  # mirror female numbers along the ordinate in order to see them
  # on the left in final plot
  geom_bar(aes(y = -Female), width = 1, stat = "identity") +
  geom_hline(yintercept = 0, colour = "white") +
  scale_x_continuous("", seq(0, 110, 10)) +
  scale_y_continuous("",
                     seq(-50000, 50000, 10000),
                     labels = function(x){format(abs(x), big.mark = ",")}) +
  scale_fill_manual("Cause of Death", values = cpal) +
  coord_flip(xlim = c(0, 110), ylim = c(-50000, 50000)) +
  theme_minimal() +
  theme(panel.grid.minor = element_blank(),
        aspect.ratio = 1.3,
        legend.position = c(0.8, 0.25),
        legend.background = element_rect(fill = NA, colour = NA),
        legend.key.size = unit(10, "pt"))

ggsave(filename = "stacked_bars.pdf", path = "./fig/raw/", width = 7, height = 9)

# Age Distribution of Each Cause of Death by Sex --------------------------

# share of deaths due to a given cause in age x on all deaths for this cause by sex
ggplot(cod_tidy, aes(x = age_years, group = sex)) +
  geom_density(aes(y = ..prop.., fill = cod_icd10_recode),
               stat = "count", colour = NA, alpha = 0.5, show.legend = FALSE) +
  geom_line(aes(y = ..prop.., linetype = sex),
            stat = "count") +
  scale_x_continuous("", seq(0, 110, 20)) +
  scale_fill_manual(values = cpal) +
  facet_wrap(~cod_icd10_recode, nrow = 5) +
  coord_cartesian(ylim = c(0, 0.1)) +
  theme_bw() +
  theme(panel.grid = element_blank(),
        panel.border = element_blank(),
        strip.background = element_blank(),
        aspect.ratio = 0.7)

ggsave(filename = "small_multiples.pdf", path = "./fig/raw/", width = 7, height = 9)
