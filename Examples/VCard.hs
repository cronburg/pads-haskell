module Text.VCard
    ( -- $doc
      VCard(..)
    , CommonName
    , IndividualNames(..)
    , VCardProperty(..)
    , AddrType(..)
    , TelType(..)
    , EmailType(..)
    , AgentData(..)
    , Data(..)
    , Class(..)
    ) where

import Data.List (intercalate)
import Data.Time (UTCTime, TimeZone, FormatTime, formatTime)
import System.Locale (defaultTimeLocale)
import Language.Pads.Haskell


-- Lines are delimited with carriage return/line-feed (control-M, newline)  \r\n
-- Nested Vcards are separated by \n rather than \r\n

[pads|
-- KSF: Added to describe sequence of VCards
type VCards = [VCcard | EOR] terminator EOF

-- KSF: moved IndividualNames and Common Name into VCardPropety because these attributes are not 
--      guaranteed to be in a particular order.
data VCard = VCard  ("BEGIN:", vcardRE, EOR, [Entry|EOR] terminator "END:", vcardRE)

type Entry = Entry { prefix   :: Maybe ("item", Int, '.'),
                     tag      :: Tag, 
                     sep      :: PstringME semicommaRE, 
                     property :: VCardProperty tag }

data Tag = VERSION | N | FN | NICKNAME | PHOTO | BDAY | ADR | LABEL
         | TEL | EMAIL | MAILER | TZ |GEO | TITLE | ROLE | LOGO | AGENT
         | ORG | CATEGORIES | NOTE | PRODID | REV | SORTSTRING "SORT-STRING"
         | SOUND | UID | URL | CLASS | KEY
         | EXTENSION ("X-", VCardString)
         | ITEM "item"

data VCardProperty (tag :: Tag) = case tag of 
    -- | Version number of VCard file format
      VERSION ->  Version (Int, '.', Int)

    -- | A breakdown of the vCard entity's name, as described by IndividualNames 
    | N -> Names IndividualNames

    -- | Formated name of the represented person
    --
    -- > CommonName "Mr. Michael A. F. Schade"
    | FN -> CommonName VCardString

    -- | A list of nicknames belonging to the VCard entity. E.g.,
    --
    -- > Nickname ["Mike", "Mikey"]
    | NICKNAME -> Nickname NameRs

    -- | A photo of the VCard entity. E.g.,
    --
    -- > Photo Nothing (URI "http://accentuate.us/smedia/images/michael.jpg")
    | PHOTO -> Photo Data

    -- | Specifies the birth date of the VCard entity. E.g.,
    --
    | BDAY -> Birthday { bdayType :: Maybe "value=date:"
                       , bdate    :: DateFSE <| ("%Y-%m-%d", RE "$") |>
                       }
    -- | A physical address associated with the vCard entity. E.g.,
    --
    -- > Address [AddrParcel, AddrPostal] "PO Box 935" "" "" "Fenton" "MO"
    -- >                                  "63026" "USA"
    | ADR -> Address   { addrType      :: TypeL AddrType
                       , poBox         :: VCardString, ';'
                       , extAddress    :: VCardString, ';'
                       , streetAddress :: VCardString, ';'
                       , locality      :: VCardString, ';' -- ^ City
                       , region        :: VCardString, ';' -- ^ State or Province
                       , postalCode    :: VCardString, ';'
                       , countryName   :: VCardString
                       }
    -- | Formatted text about the delivery address. This is typically similar
    -- to the information in Address. E.g.,
    --
    -- > Label  [AddrParcel, AddrPostal]
    -- >        ["Michael Schade", "PO Box 935", "Fenton, MO 63026"]
    | LABEL -> Label { lblType   :: TypeL AddrType
                     , label     :: VCardString
                     }
    -- | A telephone number for the VCard entity, as well as a list of
    -- properties describing the telephone number. E.g.,
    --
    -- > Telephone [TelCell, TelPreferred] "+1-555-555-5555"
    | TEL -> Telephone { telType   :: TypeL TelType
                       , number    :: VCardString
                       }
    -- | An email address for the VCard entity, including a list of properties
    -- describing it. E.g.,
    --
    -- > Email [EmailInternet, EmailPreferred] "hackage@mschade.me"
    | EMAIL -> Email { emailType :: TypeL EmailType
                     , email     :: VCardString
                     }
    -- | Specifies the mailing agent the vCard entity uses. E.g.,
    --
    -- > Mailer "MichaelMail 4.2" -- Not a real mailing agent, unfortunately :(
    | MAILER -> Mailer VCardString
    -- | Represents the time zone of the vCard entity. E.g.,
    --
    -- > TZ (hoursToTimeZone (-6))
    | TZ -> Tz TZone     

    -- | Relates to the global positioning of the vCard entity. The value is
    -- (latitude, longitude) and must be specified as decimal degrees,
    -- preferably to six decimal places.
    --
    -- > Geo (37.386013, -122.082932)
    | GEO -> Geo (Double, ';', Double)
    -- | The VCard entity's job title or other position. E.g.,
    --
    -- > Title "Co-Founder"
    | TITLE -> Title VCardString
    -- | Specifies the role associated with the title. E.g.,
    --
    -- > Role "Anything"   -- For the co-founder, or
    -- > Role "Programmer" -- For someone the title "Research and Development"
    | ROLE -> Role VCardString
    -- | An image of the vCard entity's logo. This would typically relate to
    -- their organization. E.g.,
    --
    -- > Logo Nothing (URI "http://spearheaddev.com/smedia/images/logo-trans.png")
    | LOGO -> Logo  Data
    -- | Indicates the vCard of an assistant or area administrator who is
    -- typically separately addressable. E.g.,
    --
    -- > Agent (AgentURI "CID:JQPUBLIC.part3.960129T083020.xyzMail@host3.com")
    --
    -- or
    --
    -- > Agent (AgentVCard (VCard   [ CommonName "James Q. Helpful"
    -- >                            , Email [EmailInternet] "j@spearheaddev.com"
    -- >                            ]))
    | AGENT -> Agent AgentData
    -- | The organization to which an entity belongs followed by organizational
    -- unit names. E.g.,
    --
    -- > Organization ["Spearhead Development, L.L.C.", "Executive"]
    | ORG -> Organization ([VCardString | ';'] termintor EOR)
    -- | General categories to describe the vCard entity. E.g.,
    --
    -- > Categories ["Internet", "Web Services", "Programmers"]
    | CATEGORIES -> Categories [VCardString | ','] terminator EOR
    -- | A general note about the vCard entity. E.g.,
    --
    -- > Note "Email is the absolute best contact method."
    | NOTE -> Note VCardString
    -- | Specifies the identifier of the product that created this vCard. E.g.,
    --
    -- > ProductId "-//ONLINE DIRECTORY//NONSGML Version 1//EN"
    --
    -- Please note well that, by RFC 2426 guidelines, \"implementations SHOULD
    -- use a method such as that specified for Formal Public Identifiers in ISO
    -- 9070 to assure that the text value is unique,\" but this module does not
    -- support that.
    | PRODID -> ProductId VCardString
    -- | Distinguishes the current revision from other renditions. E.g.,
    --
    -- > Revision $ UTCTime (fromGregorian 2011 04 16) (secondsToDiffTime 0)
    | REV -> Revision { revDate :: DateFSE <|("%Y-%m-%d", RE "T")|> 
                      , revTime :: Maybe ('T', DateFSE <|("%H-%M-%SZ", RE "$")|>)
                      } 
    -- | Provides a locale- or national-language-specific formatting of the
    -- formatted name based on the vCard entity's family or given name. E.g.,
    --
    -- > SortString "Schade"
    | SORTSTRING -> SortString VCardString
    -- | Specifies information in a digital sound format to annotate some
    -- aspect of the vCard. This is typically for the proper pronunciation of the
    -- vCard entity's name. E.g.,
    --
    -- > Sound  "BASIC"
    -- >        (URI "CID:JOHNQPUBLIC.part8.19960229T080000.xyzMail@host1.com")
    | SOUND -> Sound { sndType   :: Maybe (TypeS, ';') -- ^ Registered IANA format
                     , sndData   :: Data
                     }
    -- | A value to uniquely identify the vCard. Please note well that this
    -- should be one of the registered IANA formats, but as of this time, this
    -- module does not support listing the UID type. E.g.,
    --
    -- > UID "19950401-080045-40000F192713-0052"
    | UID -> Uid { uidType :: Maybe (TypeS, ';')
                   uidData :: VCardString }
    -- | A website associated with the vCard entity. E.g.,
    --
    -- > URL "http://spearheaddev.com/"
    | URL -> Url VCardString
    -- | Describes the general intention of the vCard owner as to how
    -- accessible the included information should be. E.g.,
    --
    -- > Class ClassConfidential
    | CLASS Class
    -- | Specifies a public key or authentication certificate associated with
    -- the vCard entity. E.g.,
    --
    -- > Key "x509" (Binary "dGhpcyBjb3VsZCBiZSAKbXkgY2VydGlmaWNhdGUK")
    | KEY -> Key { keyType   :: Maybe (TypeS, ';') -- ^ Registered IANA format
                 , keyData   :: Data
                 }
    | EXTENSION s -> VCardString    

-- | A breakdown of the vCard entity's name, corresponding, in sequence, to
-- Family Name, Given Name, Additional Names, Honorific Prefixes, and Honorific
-- Suffixes. E.g.,
--
-- > IndividualNames ["Schade"] ["Michael"] ["Anthony", "Fanetti"] [] ["Esq."]
data IndividualNames =  IndividualNames { familyName        :: NameSs
                                        , givenName         :: NameSs
                                        , additionalNames   :: NameSs
                                        , honorificPrefixes :: NameSs
                                        , honorificSuffixes :: NameSs
                                        }

data TZone = TzText ("VALUE=text:", Stringln)
           | TzInt  (TimeZoneSE <| RE "$" |>)


-- | Represents the various types or properties of an address.
data AddrType   = AddrDomestic (PstringME "DOM|dom")
                | AddrInternational (PstringME "INTL|intl")
                | AddrPostal (PstringME "POSTAL|postal")
                | AddrParcel (PstringME "PARCEL|parcel")
                | AddrHome (PstringME "HOME|home")
                | AddrWork (PstringME "WORK|work")
                | AddrPreferred (PstringME "PREF|pref")

-- | Represents the various types or properties of a telephone number.
data TelType    = TelHome "HOME"
                | TelMessage "MSG"
                | TelWork "WORK"
                | TelVoice "VOICE"
                | TelFax "FAX"
                | TelCell "CELL"
                | TelVideo "VIDEO"
                | TelPager "PAGER"
                | TelBBS "BBS"
                | TelModem "MODEM"
                | TelCar "CAR"
                | TelISDN "ISDN"
                | TelPCS "PCS"
                | TelPreferred (PstringME "PREF|pref")

-- | Represents the various types or properties of an email address.
data EmailType = EmailInternet "INTERNET"
               | EmailX400  "X400"
               | EmailPreferred (PstringME "PREF|pref")

-- | Represents the data associated with a vCard's Agent. This could be a URI
-- to such a vCard or the embedded contents of the vCard itself.
data AgentData = AgentURI ("VALUE=uri:", VCardString)
               | AgentVCard VCard

-- | Represents the various types of data that can be included in a vCard.
data Data = URI    ("VALUE=uri:", VCardString) 
          | Binary ("ENCODING=b", Maybe(';', TypeS), ':', WrappedEncoding )
          | Base64 ("BASE64:", WrappedEncoding)

type WrappedEncoding = [Line (StringlnP startsWithSpace)]

-- | Classifies the vCard's intended access level.
data Class = ClassPublic "PUBLIC"
           | ClassPrivate "PRIVATE"
           | ClassConfidential "CONFIDENTIAL"

-- Need to code base type StringESC.  It takes a list of pairs.
-- Each pair represents a stopping condition.
-- If parser sees first component of tuple, it stops.
-- Second component is prefix to escape first component, so //, does not stop.
-- Pretty printer prefixes stopping components with escape sequence.
type VCardString = StringESC [(',', "\\"), (';', "\\"), (':', "\\")]   
type NameSs = [VCardString | ','] terminator ';'
type NameRs = [VCardString | ','] terminator EOR

type TypeS = (typeRE, '=', [VCardString|','] terminator (Try (RE "[:;]")))
type TypeL a = [(typeRE, '=', [a|','] terminator (Try ';'))|';'] terminator ':')

|]

semicommaRE = RE "[;,]"
vcardRE = REd "VCARD|vCard" "VCARD"
typeRE = REd "TYPE|type" "TYPE"


startsWithSpace (PstringSE s) = case s of 
   [] -> False
   ' ':s' -> True
   '\t':s' -> True
   '\v':s' -> True
   otherwise -> False

-- $doc
--
-- This package implements the RFC 2426 vCard 3.0 spec
-- (<http://www.ietf.org/rfc/rfc2426.txt>)
--
-- Its usage is fairly simple and intuitive. For example, below is how one
-- would produce a VCard for Frank Dawson, one of the RFC 2426 authors:
--
-- > VCard  "Frank Dawson"
-- >        (IndividualNames ["Dawson"] ["Frank"] [] [] [])
-- >        [ Organization ["Lotus Development Corporation"]
-- >        , Address [AddrWork, AddrPostal, AddrParcel] "" ""
-- >                    "6544 Battleford Drive"
-- >                    "Raleigh" "NC" "27613-3502" "U.S.A"
-- >        , Telephone [TelVoice, TelMessage, TelWork] "+1-919-676-9515"
-- >        , Telephone [TelFax, TelWork] "+1-919-676-9564"
-- >        , Email [EmailInternet, EmailPreferred] "Frank_Dawson@Lotus.com"
-- >        , Email [EmailInternet] "fdawson@earthlink.net"
-- >        , URL "http://home.earthlink.net/~fdawson"
-- >        ]
--
-- Although this package is fairly well documented, even with general
-- explanations about the various VCard properties, RFC 2426 should be
-- consulted for the final say on the meaning or application of any of the
-- VCard properties.