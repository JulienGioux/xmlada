-----------------------------------------------------------------------
--                XML/Ada - An XML suite for Ada95                   --
--                                                                   --
--                       Copyright (C) 2010, AdaCore                 --
--                                                                   --
-- This library is free software; you can redistribute it and/or     --
-- modify it under the terms of the GNU General Public               --
-- License as published by the Free Software Foundation; either      --
-- version 2 of the License, or (at your option) any later version.  --
--                                                                   --
-- This library is distributed in the hope that it will be useful,   --
-- but WITHOUT ANY WARRANTY; without even the implied warranty of    --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU --
-- General Public License for more details.                          --
--                                                                   --
-- You should have received a copy of the GNU General Public         --
-- License along with this library; if not, write to the             --
-- Free Software Foundation, Inc., 59 Temple Place - Suite 330,      --
-- Boston, MA 02111-1307, USA.                                       --
--                                                                   --
-- As a special exception, if other files instantiate generics from  --
-- this unit, or you link this unit with other files to produce an   --
-- executable, this  unit  does not  by itself cause  the resulting  --
-- executable to be covered by the GNU General Public License. This  --
-- exception does not however invalidate any other reasons why the   --
-- executable file  might be covered by the  GNU Public License.     --
-----------------------------------------------------------------------

pragma Ada_05;

with Ada.Exceptions;            use Ada.Exceptions;
with Ada.Strings.Fixed;         use Ada.Strings.Fixed;
with Ada.Strings.Unbounded;     use Ada.Strings.Unbounded;
with Sax.Encodings;             use Sax.Encodings;
with Unicode;                   use Unicode;
with Unicode.Names.Basic_Latin; use Unicode.Names.Basic_Latin;

package body Schema.Simple_Types is

   use Simple_Type_Tables, Enumeration_Tables;

   generic
      with function Get_Length (Ch : Byte_Sequence) return Natural;
   function Validate_Length_Facets
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   --  Validate length facets

   generic
      type T is private;
      Unknown_T : T;
      with procedure Value (Symbols : Symbol_Table;
                            Ch      : Byte_Sequence;
                            Val     : out T;
                            Error   : out Symbol) is <>;
      with function Image (Val : T) return Byte_Sequence is <>;
      with function "=" (T1, T2 : T) return Boolean is <>;
      with function "<" (T1, T2 : T) return Boolean is <>;
      with function "<=" (T1, T2 : T) return Boolean is <>;
   procedure Validate_Range
     (Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence;
      Min_Inclusive : T;
      Min_Exclusive : T;
      Max_Inclusive : T;
      Max_Exclusive : T;
      Error         : out Symbol;
      Val           : out T);

   generic
      type T is private;
      with procedure Value (Symbols : Symbol_Table;
                            Ch      : Byte_Sequence;
                            Val     : out T;
                            Error   : out Symbol) is <>;
   procedure Override_Single_Range_Facet
     (Symbols       : Sax.Utils.Symbol_Table;
      Facet         : Facet_Value;
      Val           : in out T;
      Error         : in out Symbol;
      Error_Loc     : in out Location);

   generic
      type T is private;
      with procedure Value (Symbols : Symbol_Table;
                            Ch      : Byte_Sequence;
                            Val     : out T;
                            Error   : out Symbol) is <>;
   procedure Override_Range_Facets
     (Symbols       : Sax.Utils.Symbol_Table;
      Facets        : All_Facets;
      Min_Inclusive : in out T;
      Min_Exclusive : in out T;
      Max_Inclusive : in out T;
      Max_Exclusive : in out T;
      Error         : out Symbol;
      Error_Loc     : out Location);
   --  Override some range facets

   generic
      type T is private;
      with procedure Value (Symbols : Symbol_Table;
                            Ch      : Byte_Sequence;
                            Val     : out T;
                            Error   : out Symbol) is <>;
      with function "=" (T1, T2 : T) return Boolean is <>;
   function Generic_Equal
     (Symbols : Symbol_Table;
      Val1    : Symbol;
      Val2    : Byte_Sequence) return Boolean;
   --  Compare two values, after possibly normalizing them given the type
   --  definition (whitespaces, remove left-most 0 when appropriate,...).
   --  This assumes [Val1] and [Val2] are valid values for the type (ie they
   --  have already been validated).

   -------------------
   -- Generic_Equal --
   -------------------

   function Generic_Equal
     (Symbols : Symbol_Table;
      Val1    : Symbol;
      Val2    : Byte_Sequence) return Boolean
   is
      V1, V2 : T;
      Error  : Symbol;
   begin
      Value (Symbols, Get (Val1).all, V1, Error);
      Value (Symbols, Val2, V2, Error);
      return V1 = V2;
   end Generic_Equal;

   ----------------------------
   -- Validate_Length_Facets --
   ----------------------------

   function Validate_Length_Facets
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Length : Integer := -1;
   begin
      --  Characters are always a string, nothing to check here but the facets

      if Descr.String_Length /= Natural'Last then
         Length := Get_Length (Ch);
         if Length /= Descr.String_Length then
            return Find
              (Symbols,
               "#Invalid length, must be"
               & Integer'Image (Descr.String_Length) & " characters");
         end if;
      end if;

      if Descr.String_Min_Length /= 0 then
         if Length /= -1 then
            Length := Get_Length (Ch);
         end if;

         if Length < Descr.String_Min_Length then
            return Find
              (Symbols,
               "#String is too short, minimum length is"
               & Integer'Image (Descr.String_Min_Length)
               & " characters");
         end if;
      end if;

      if Descr.String_Max_Length /= 0 then
         if Length /= -1 then
            Length := Get_Length (Ch);
         end if;

         if Length > Descr.String_Max_Length then
            return Find
              (Symbols,
               "#String is too long, maximum length is"
               & Integer'Image (Descr.String_Max_Length)
               & " characters");
         end if;
      end if;

      return No_Symbol;
   end Validate_Length_Facets;

   ---------------------
   --  Instantiations --
   ---------------------

   function HexBinary_Get_Length
     (Value : Unicode.CES.Byte_Sequence) return Natural;
   function Base64Binary_Get_Length
     (Value : Unicode.CES.Byte_Sequence) return Natural;
   --  Return the length of a string

   procedure Value (Symbols : Symbol_Table;
                    Ch      : Byte_Sequence;
                    Val     : out XML_Float;
                    Error   : out Symbol);
   --  Converts [Ch] into [Val]

   function Validate_String is new
     Validate_Length_Facets (Encoding.Length.all);
   function Validate_HexBinary_Facets is new
     Validate_Length_Facets (HexBinary_Get_Length);
   function Validate_Base64Binary_Facets is new
     Validate_Length_Facets (Base64Binary_Get_Length);

   function Validate_NMTOKEN
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_NMTOKENS
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Name
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_NCName
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_NCNames
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Language
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_URI
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_HexBinary
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Base64Binary
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_QName
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Boolean
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Double
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Decimal
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Duration
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Date_Time
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Date
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_Time
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_GDay
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_GMonth_Day
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_GMonth
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_GYear
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   function Validate_GYear_Month
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol;
   --  Check [Ch] for one of the primitive types, including facets

   function Equal_String
     (Descr : Simple_Type_Descr;
      Symbols : Symbol_Table;
      Ch1   : Symbol;
      Ch2   : Byte_Sequence) return Boolean;
   --  Compare values

   function Anchor (Str : String) return String;
   --  Return an anchored version of Str ("^...$").
   --  In XML, regexps are always anchored, as per the beginning of [G]

   function Missing_End_Anchor (Str : String) return Boolean;
   function Missing_Start_Anchor (Str : String) return Boolean;
   --  Whether the regexp is missing the "^" or "$" anchors

   procedure Boolean_Value
     (Symbols : Symbol_Table;
      Ch      : Byte_Sequence;
      Val     : out Boolean;
      Error   : out Symbol);
   --  Converts [Ch] to a boolean, and returns an error message if needed

   function Equal_Boolean     is new Generic_Equal (Boolean, Boolean_Value);
   function Equal_Float       is new Generic_Equal (XML_Float, Value);
   function Equal_Decimal    is new Generic_Equal (Arbitrary_Precision_Number);
   function Equal_Duration    is new Generic_Equal (Duration_T);
   function Equal_Date_Time   is new Generic_Equal (Duration_T);
   function Equal_Date        is new Generic_Equal (Duration_T);
   function Equal_Time        is new Generic_Equal (Time_T);
   function Equal_GDay        is new Generic_Equal (GDay_T);
   function Equal_GMonth_Day  is new Generic_Equal (GMonth_Day_T);
   function Equal_GMonth      is new Generic_Equal (GMonth_T);
   function Equal_GYear       is new Generic_Equal (GYear_T);
   function Equal_GYear_Month is new Generic_Equal (GYear_Month_T);

   -------------------------------
   -- Register_Predefined_Types --
   -------------------------------

   procedure Register_Predefined_Types (Symbols : Sax.Utils.Symbol_Table) is
      Zero : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "0"));
      One  : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "1"));
      Minus_One  : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "-1"));
      Max_Unsigned_Long : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+18446744073709551615"));
      Max_Long : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+9223372036854775807"));
      Min_Long : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "-9223372036854775808"));
      Max_Int : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+2147483647"));
      Min_Int : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "-2147483648"));
      Max_Short : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+32767"));
      Min_Short : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "-32768"));
      Max_Byte : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+127"));
      Min_Byte : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "-128"));
      Max_Unsigned_Int : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+4294967295"));
      Max_Unsigned_Short : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+65535"));
      Max_Unsigned_Byte : constant Arbitrary_Precision_Number :=
        Value (Find (Symbols, "+255"));

   begin
      Register ("anySimpleType", (Kind       => Facets_String,
                                  Whitespace => Preserve,
                                  others     => <>));
      Register ("string", (Kind       => Facets_String,
                           Whitespace => Preserve,
                           others     => <>));
      Register ("normalizedString", (Kind => Facets_String,
                                     Whitespace => Replace,
                                     others => <>));
      Register ("token", (Kind => Facets_String,
                          Whitespace => Collapse,
                          others => <>));
      Register ("language", (Kind => Facets_Language,
                             Whitespace => Preserve,
                             others => <>));
      Register ("boolean",  (Kind => Facets_Boolean, others => <>));
      Register ("QName",    (Kind => Facets_QName, others => <>));
      Register ("NOTATION", (Kind => Facets_QName, others => <>));
      Register ("float",    (Kind => Facets_Float, others => <>));
      Register ("NMTOKEN",  (Kind => Facets_NMTOKEN, others => <>));
      Register ("NMTOKENS", (Kind => Facets_NMTOKENS, others => <>));
      Register ("Name",     (Kind => Facets_Name,
                             Whitespace => Preserve,
                             others => <>));
      Register ("NCName",   (Kind => Facets_NCName,
                             Whitespace => Preserve,
                             others => <>));
      Register ("ID",       (Kind => Facets_NCName,
                             Whitespace => Preserve,
                             others => <>));
      Register ("IDREF",    (Kind => Facets_NCName,
                             Whitespace => Preserve,
                             others => <>));
      Register ("IDREFS",   (Kind => Facets_NCNames,
                             Whitespace => Preserve,
                             others => <>));
      Register ("ENTITY",   (Kind => Facets_NCName,
                             Whitespace => Preserve,
                             others => <>));
      Register ("ENTITIES", (Kind => Facets_NCNames,
                             Whitespace => Preserve,
                             others => <>));
      Register ("anyURI",   (Kind => Facets_Any_URI,
                             others => <>));
      Register ("hexBinary", (Kind => Facets_HexBinary,
                              others => <>));
      Register ("base64Binary", (Kind => Facets_Base64Binary,
                                 others => <>));
      Register ("decimal", (Kind => Facets_Decimal, others => <>));
      Register ("unsignedLong", (Kind                  => Facets_Decimal,
                                 Fraction_Digits       => 0,
                                 Decimal_Min_Inclusive => Zero,
                                 Decimal_Max_Inclusive => Max_Unsigned_Long,
                                 others                => <>));
      Register ("integer",      (Kind                  => Facets_Decimal,
                                 Fraction_Digits       => 0,
                                 others                => <>));
      Register ("nonNegativeInteger", (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Min_Inclusive => Zero,
                                       others                => <>));
      Register ("positiveInteger",    (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Min_Inclusive => One,
                                       others                => <>));
      Register ("nonPositiveInteger", (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Zero,
                                       others                => <>));
      Register ("negativeInteger",    (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Minus_One,
                                       others                => <>));
      Register ("long",               (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Max_Long,
                                       Decimal_Min_Inclusive => Min_Long,
                                       others                => <>));
      Register ("int",                (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Max_Int,
                                       Decimal_Min_Inclusive => Min_Int,
                                       others                => <>));
      Register ("short",              (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Max_Short,
                                       Decimal_Min_Inclusive => Min_Short,
                                       others                => <>));
      Register ("byte",               (Kind                  => Facets_Decimal,
                                       Fraction_Digits       => 0,
                                       Decimal_Max_Inclusive => Max_Byte,
                                       Decimal_Min_Inclusive => Min_Byte,
                                       others                => <>));
      Register ("unsignedInt",      (Kind                  => Facets_Decimal,
                                     Fraction_Digits       => 0,
                                     Decimal_Max_Inclusive => Max_Unsigned_Int,
                                     Decimal_Min_Inclusive => Zero,
                                     others                => <>));
      Register ("unsignedShort",  (Kind                  => Facets_Decimal,
                                   Fraction_Digits       => 0,
                                   Decimal_Max_Inclusive => Max_Unsigned_Short,
                                   Decimal_Min_Inclusive => Zero,
                                   others                => <>));
      Register ("unsignedByte",   (Kind                  => Facets_Decimal,
                                   Fraction_Digits       => 0,
                                   Decimal_Max_Inclusive => Max_Unsigned_Byte,
                                   Decimal_Min_Inclusive => Zero,
                                   others                => <>));
      Register ("float",      (Kind => Facets_Float, others => <>));
      Register ("double",     (Kind => Facets_Double, others => <>));
      Register ("time",       (Kind => Facets_Time, others => <>));
      Register ("dateTime",   (Kind => Facets_DateTime, others => <>));
      Register ("gDay",       (Kind => Facets_GDay, others => <>));
      Register ("gMonthDay",  (Kind => Facets_GMonthDay, others => <>));
      Register ("gMonth",     (Kind => Facets_GMonth, others => <>));
      Register ("gYearMonth", (Kind => Facets_GYearMonth, others => <>));
      Register ("gYear",      (Kind => Facets_GYear, others => <>));
      Register ("date",       (Kind => Facets_Date, others => <>));
      Register ("duration",   (Kind => Facets_Duration, others => <>));

      --  Missing attribute "xml:lang" of type "language"
   end Register_Predefined_Types;

   -----------
   -- Equal --
   -----------

   function Equal
     (Simple_Types  : Simple_Type_Table;
      Symbols       : Symbol_Table;
      Simple_Type   : Simple_Type_Index;
      Ch1           : Sax.Symbols.Symbol;
      Ch2           : Unicode.CES.Byte_Sequence) return Boolean
   is
      Descr : Simple_Type_Descr renames Simple_Types.Table (Simple_Type);
   begin
      case Descr.Kind is
         when Facets_String .. Facets_HexBinary =>
            return Equal_String (Descr, Symbols, Ch1, Ch2);
         when Facets_Boolean   => return Equal_Boolean (Symbols, Ch1, Ch2);
         when Facets_Float | Facets_Double  =>
            return Equal_Float (Symbols, Ch1, Ch2);
         when Facets_Decimal   => return Equal_Decimal (Symbols, Ch1, Ch2);
         when Facets_Time      => return Equal_Time (Symbols, Ch1, Ch2);
         when Facets_DateTime  => return Equal_Date_Time (Symbols, Ch1, Ch2);
         when Facets_GDay      => return Equal_GDay (Symbols, Ch1, Ch2);
         when Facets_GMonth    => return Equal_GMonth (Symbols, Ch1, Ch2);
         when Facets_GYear     => return Equal_GYear (Symbols, Ch1, Ch2);
         when Facets_Date      => return Equal_Date (Symbols, Ch1, Ch2);
         when Facets_Duration  => return Equal_Duration (Symbols, Ch1, Ch2);
         when Facets_GMonthDay =>
            return Equal_GMonth_Day (Symbols, Ch1, Ch2);
         when Facets_GYearMonth =>
            return Equal_GYear_Month (Symbols, Ch1, Ch2);

         when Facets_Union =>
            for S in Descr.Union'Range loop
               if Descr.Union (S) /= No_Simple_Type_Index then
                  if Equal
                    (Simple_Types => Simple_Types,
                     Symbols      => Symbols,
                     Simple_Type  => Descr.Union (S),
                     Ch1          => Ch1,
                     Ch2          => Ch2)
                  then
                     return True;
                  end if;
               end if;
            end loop;
            return False;
      end case;
   end Equal;

   -------------------------------------
   -- Validate_Simple_Type_Characters --
   -------------------------------------

   function Validate_Simple_Type
     (Simple_Types  : Simple_Type_Table;
      Enumerations  : Enumeration_Tables.Instance;
      Symbols       : Symbol_Table;
      Simple_Type   : Simple_Type_Index;
      Ch            : Unicode.CES.Byte_Sequence;
      Empty_Element : Boolean) return Symbol
   is
      Descr : Simple_Type_Descr renames Simple_Types.Table (Simple_Type);
      Index : Integer;
      Char  : Unicode_Char;
      Matched : Match_Array (0 .. 0);
      Error   : Symbol;

   begin
      if Descr.Kind = Facets_Union then
         for S in Descr.Union'Range loop
            if Descr.Union (S) /= No_Simple_Type_Index then
               Error := Validate_Simple_Type
                 (Simple_Types  => Simple_Types,
                  Enumerations  => Enumerations,
                  Symbols       => Symbols,
                  Simple_Type   => Descr.Union (S),
                  Ch            => Ch,
                  Empty_Element => Empty_Element);
               if Error = No_Symbol then
                  return Error;
               else
                  if Debug then
                     Debug_Output ("Checking union at index" & S'Img
                                   & " => " & Get (Error).all);
                  end if;
               end if;
            end if;
         end loop;
         return Find (Symbols, "No matching type in the union");
      end if;

      --  Check common facets

      if Descr.Enumeration /= No_Enumeration_Index then
         declare
            Enum  : Enumeration_Index := Descr.Enumeration;
            Found : Boolean := False;
         begin
            while Enum /= No_Enumeration_Index loop
               if Get (Enumerations.Table (Enum).Value).all = Ch then
                  Found := True;
                  exit;
               end if;

               Enum := Enumerations.Table (Enum).Next;
            end loop;

            if not Found then
               return Find
                 (Symbols, "Value not in the enumeration set");
            end if;
         end;
      end if;

      if Descr.Pattern_String /= No_Symbol then

         --  Check whether we have unicode char outside of ASCII

         Index := Ch'First;
         while Index <= Ch'Last loop
            Encoding.Read (Ch, Index, Char);
            if Char > 127 then
               return Find
                 (Symbols, "Regexp matching with unicode not supported");
            end if;
         end loop;

         Match (Descr.Pattern.all, String (Ch), Matched);
         if Matched (0).First /= Ch'First
           or else Matched (0).Last /= Ch'Last
         then
            return Find
              (Symbols,
               "string pattern not matched: "
               & Get (Descr.Pattern_String).all);
         end if;
      end if;

      case Descr.Whitespace is
         when Preserve =>
            null; --  Always valid

         when Replace =>
            for C in Ch'Range loop
               if Ch (C) = ASCII.HT
                 or else Ch (C) = ASCII.LF
                 or else Ch (C) = ASCII.CR
               then
                  return Find
                    (Symbols, "HT, LF and CR characters not allowed");
               end if;
            end loop;

         when Collapse =>
            for C in Ch'Range loop
               if Ch (C) = ASCII.HT
                 or else Ch (C) = ASCII.LF
                 or else Ch (C) = ASCII.CR
               then
                  return Find
                    (Symbols, "HT, LF and CR characters not allowed");

               elsif Ch (C) = ' '
                 and then C < Ch'Last
                 and then Ch (C + 1) = ' '
               then
                  return Find
                    (Symbols, "Duplicate space characters not allowed");
               end if;
            end loop;

            --  Leading or trailing white spaces are also forbidden
            if Ch'Length /= 0 then
               if Ch (Ch'First) = ' ' then
                  return Find
                    (Symbols, "Leading whitespaces not allowed");
               elsif Ch (Ch'Last) = ' ' then
                  return Find
                    (Symbols, "Trailing whitespaces not allowed");
               end if;
            end if;
      end case;

      --  Type-specific facets

      case Descr.Kind is
         when Facets_String | Facets_Notation =>
            return Validate_String (Descr, Symbols, Ch);
         when Facets_HexBinary =>
            return Validate_HexBinary (Descr, Symbols, Ch);
         when Facets_Base64Binary =>
            return Validate_Base64Binary (Descr, Symbols, Ch);
         when Facets_Language => return Validate_Language (Descr, Symbols, Ch);
         when Facets_QName    => return Validate_QName (Descr, Symbols, Ch);
         when Facets_NCName   => return Validate_NCName (Descr, Symbols, Ch);
         when Facets_NCNames  => return Validate_NCNames (Descr, Symbols, Ch);
         when Facets_Name     => return Validate_Name (Descr, Symbols, Ch);
         when Facets_Any_URI  => return Validate_URI (Descr, Symbols, Ch);
         when Facets_NMTOKEN  => return Validate_NMTOKEN (Descr, Symbols, Ch);
         when Facets_NMTOKENS => return Validate_NMTOKENS (Descr, Symbols, Ch);
         when Facets_Boolean  => return Validate_Boolean (Descr, Symbols, Ch);
         when Facets_Decimal  => return Validate_Decimal (Descr, Symbols, Ch);
         when Facets_Float | Facets_Double  =>
            return Validate_Double (Descr, Symbols, Ch);
         when Facets_Time     => return Validate_Time (Descr, Symbols, Ch);
         when Facets_DateTime =>
            return Validate_Date_Time (Descr, Symbols, Ch);
         when Facets_GDay => return Validate_GDay (Descr, Symbols, Ch);
         when Facets_GMonthDay =>
            return Validate_GMonth_Day (Descr, Symbols, Ch);
         when Facets_GMonth   => return Validate_GMonth (Descr, Symbols, Ch);
         when Facets_GYearMonth =>
            return Validate_GYear_Month (Descr, Symbols, Ch);
         when Facets_GYear    => return Validate_GYear (Descr, Symbols, Ch);
         when Facets_Date     => return Validate_Date (Descr, Symbols, Ch);
         when Facets_Duration => return Validate_Duration (Descr, Symbols, Ch);
         when Facets_Union    => return No_Symbol;  --  Already handled above
      end case;
   end Validate_Simple_Type;

   --------------------------
   -- HexBinary_Get_Length --
   --------------------------

   function HexBinary_Get_Length
     (Value : Unicode.CES.Byte_Sequence) return Natural is
   begin
      return Sax.Encodings.Encoding.Length (Value) / 2;
   end HexBinary_Get_Length;

   -----------------------------
   -- Base64Binary_Get_Length --
   -----------------------------

   function Base64Binary_Get_Length
     (Value : Unicode.CES.Byte_Sequence) return Natural
   is
      Length : Natural := 0;
      C : Unicode_Char;
      Index : Positive := Value'First;
   begin
      while Index <= Value'Last loop
         Sax.Encodings.Encoding.Read (Value, Index, C);
         if C /= 16#20#
           and then C /= 16#A#
           and then C /= Character'Pos ('=')
         then
            Length := Length + 1;
         end if;
      end loop;
      return Length * 3 / 4;
   end Base64Binary_Get_Length;

   ----------------------
   -- Validate_NMTOKEN --
   ----------------------

   function Validate_NMTOKEN
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_Nmtoken (Ch) then
         return Find (Symbols, "Invalid NMTOKEN: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_NMTOKEN;

   -----------------------
   -- Validate_NMTOKENS --
   -----------------------

   function Validate_NMTOKENS
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_Nmtokens (Ch) then
         return Find (Symbols, "Invalid NMTOKENS: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_NMTOKENS;

   -------------------
   -- Validate_Name --
   -------------------

   function Validate_Name
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_Name (Ch) then
         return Find (Symbols, "Invalid Name: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_Name;

   ---------------------
   -- Validate_NCName --
   ---------------------

   function Validate_NCName
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_NCname (Ch) then
         return Find (Symbols, "Invalid NCName: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_NCName;

   ----------------------
   -- Validate_NCNames --
   ----------------------

   function Validate_NCNames
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_NCnames (Ch) then
         return Find (Symbols, "Invalid NCName: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_NCNames;

   -----------------------
   -- Validate_Language --
   -----------------------

   function Validate_Language
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_Language_Name (Ch) then
         return Find (Symbols, "Invalid language: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_Language;

   --------------------
   -- Validate_QName --
   --------------------

   function Validate_QName
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_QName (Ch) then
         return Find (Symbols, "Invalid QName: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_QName;

   ------------------
   -- Validate_URI --
   ------------------

   function Validate_URI
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_URI (Ch) then
         return Find (Symbols, "Invalid anyURI: """ & Ch & """");
      end if;
      return Validate_String (Descr, Symbols, Ch);
   end Validate_URI;

   ------------------------
   -- Validate_HexBinary --
   ------------------------

   function Validate_HexBinary
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_HexBinary (Ch) then
         return Find (Symbols, "Invalid hexBinary: """ & Ch & """");
      end if;
      return Validate_HexBinary_Facets (Descr, Symbols, Ch);
   end Validate_HexBinary;

   ---------------------------
   -- Validate_Base64Binary --
   ---------------------------

   function Validate_Base64Binary
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol is
   begin
      if not Is_Valid_Base64Binary (Ch) then
         return Find (Symbols, "Invalid base64Binary: """ & Ch & """");
      end if;
      return Validate_Base64Binary_Facets (Descr, Symbols, Ch);
   end Validate_Base64Binary;

   -------------------
   -- Boolean_Value --
   -------------------

   procedure Boolean_Value
     (Symbols : Symbol_Table;
      Ch      : Byte_Sequence;
      Val     : out Boolean;
      Error   : out Symbol)
   is
      First : Integer;
      Index : Integer;
      C     : Unicode_Char;
   begin
      Val := False;

      if Ch = "" then
         Error := Find (Symbols, "#Invalid value for boolean type: """"");
         return;
      end if;

      --  Check we do have a valid boolean representation (skip leading spaces)

      First := Ch'First;

      while First <= Ch'Last loop
         Index := First;
         Encoding.Read (Ch, First, C);
         exit when not Is_White_Space (C);
      end loop;

      if C = Digit_Zero or C = Digit_One then
         Val := C = Digit_One;
         if First <= Ch'Last then
            Encoding.Read (Ch, First, C);
         end if;

      elsif Index + True_Sequence'Length - 1 <= Ch'Last
        and then Ch (Index .. Index + True_Sequence'Length - 1) = True_Sequence
      then
         First := Index + True_Sequence'Length;
         Val := True;

      elsif Index + False_Sequence'Length - 1 <= Ch'Last
        and then Ch (Index .. Index + False_Sequence'Length - 1) =
          False_Sequence
      then
         First := Index + False_Sequence'Length;
         Val := False;

      else
         Error := Find
           (Symbols, "#Invalid value for boolean type: """ & Ch & """");
         return;
      end if;

      --  Skip trailing spaces

      while First <= Ch'Last loop
         Encoding.Read (Ch, First, C);
         if not Is_White_Space (C) then
            Error := Find
              (Symbols, "#Invalid value for boolean type: """ & Ch & """");
            return;
         end if;
      end loop;

      Error := No_Symbol;
   end Boolean_Value;

   ----------------------
   -- Validate_Boolean --
   ----------------------

   function Validate_Boolean
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      pragma Unreferenced (Descr);
      Val   : Boolean;
      Error : Symbol;
   begin
      Boolean_Value (Symbols, Ch, Val, Error);
      if Error /= No_Symbol then
         return Error;
      end if;

      return No_Symbol;
   end Validate_Boolean;

   -----------
   -- Value --
   -----------

   procedure Value (Symbols : Symbol_Table;
                    Ch      : Byte_Sequence;
                    Val     : out XML_Float;
                    Error   : out Symbol) is
   begin
      begin
         Val := Value (Ch);
      exception
         when Constraint_Error =>
            Error := Find (Symbols, "#Invalid value: """ & Ch & """");
            return;
      end;
      Error := No_Symbol;
   end Value;

   --------------------
   -- Validate_Range --
   --------------------

   procedure Validate_Range
     (Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence;
      Min_Inclusive : T;
      Min_Exclusive : T;
      Max_Inclusive : T;
      Max_Exclusive : T;
      Error         : out Symbol;
      Val           : out T) is
   begin
      Value
        (Symbols  => Symbols,
         Ch       => Ch,
         Val      => Val,
         Error    => Error);
      if Error /= No_Symbol then
         return;
      end if;

      if Min_Inclusive /= Unknown_T then
         if Val < Min_Inclusive then
            Error := Find
              (Symbols,
               Ch & " is smaller than minInclusive ("
               & Image (Min_Inclusive) & ")");
            return;
         end if;
      end if;

      if Min_Exclusive /= Unknown_T then
         if Val <= Min_Exclusive then
            Error := Find
              (Symbols,
               Ch & " is smaller than minExclusive ("
               & Image (Min_Exclusive) & ")");
            return;
         end if;
      end if;

      if Max_Inclusive /= Unknown_T then
         if Max_Inclusive < Val then
            Error := Find
              (Symbols,
               Ch & " is greater than maxInclusive ("
               & Image (Max_Inclusive) & ")");
            return;
         end if;
      end if;

      if Max_Exclusive /= Unknown_T then
         if Max_Exclusive <= Val then
            Error := Find
              (Symbols,
               Ch & " is smaller than maxExclusive ("
               & Image (Max_Exclusive) & ")");
            return;
         end if;
      end if;
   end Validate_Range;

   procedure Validate_Double_Facets is new Validate_Range
     (XML_Float, Unknown_Float);
   procedure Validate_Decimal_Facets is new Validate_Range
     (Arbitrary_Precision_Number, Undefined_Number,
      Value => Value_No_Exponent);
   procedure Validate_Duration_Facets is new Validate_Range
     (Duration_T, No_Duration);
   procedure Validate_Date_Time_Facets is new Validate_Range
     (Date_Time_T, No_Date_Time);
   procedure Validate_Date_Facets is new Validate_Range
     (Date_T, No_Date_T);
   procedure Validate_Time_Facets is new Validate_Range
     (Time_T, No_Time_T);
   procedure Validate_GDay_Facets is new Validate_Range
     (GDay_T, No_GDay);
   procedure Validate_GMonth_Day_Facets is new Validate_Range
     (GMonth_Day_T, No_Month_Day);
   procedure Validate_GMonth_Facets is new Validate_Range
     (GMonth_T, No_Month);
   procedure Validate_GYear_Facets is new Validate_Range
     (GYear_T, No_Year);
   procedure Validate_GYear_Month_Facets is new Validate_Range
     (GYear_Month_T, No_Year_Month);

   ---------------------
   -- Validate_Double --
   ---------------------

   function Validate_Double
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : XML_Float;
      Error : Symbol;
   begin
      Validate_Double_Facets
        (Symbols, Ch, Descr.Float_Min_Inclusive,
         Descr.Float_Min_Exclusive, Descr.Float_Max_Inclusive,
         Descr.Float_Max_Exclusive, Error, Val);
      return Error;
   end Validate_Double;

   -----------------------
   -- Validate_Duration --
   -----------------------

   function Validate_Duration
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : Duration_T;
      Error : Symbol;
   begin
      Validate_Duration_Facets
        (Symbols, Ch,
         Descr.Duration_Min_Inclusive, Descr.Duration_Min_Exclusive,
         Descr.Duration_Max_Inclusive, Descr.Duration_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_Duration;

   ------------------------
   -- Validate_Date_Time --
   ------------------------

   function Validate_Date_Time
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : Date_Time_T;
      Error : Symbol;
   begin
      Validate_Date_Time_Facets
        (Symbols, Ch,
         Descr.DateTime_Min_Inclusive, Descr.DateTime_Min_Exclusive,
         Descr.DateTime_Max_Inclusive, Descr.DateTime_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_Date_Time;

   -------------------
   -- Validate_Date --
   -------------------

   function Validate_Date
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : Date_T;
      Error : Symbol;
   begin
      Validate_Date_Facets
        (Symbols, Ch,
         Descr.Date_Min_Inclusive, Descr.Date_Min_Exclusive,
         Descr.Date_Max_Inclusive, Descr.Date_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_Date;

   -------------------
   -- Validate_Time --
   -------------------

   function Validate_Time
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : Time_T;
      Error : Symbol;
   begin
      Validate_Time_Facets
        (Symbols, Ch,
         Descr.Time_Min_Inclusive, Descr.Time_Min_Exclusive,
         Descr.Time_Max_Inclusive, Descr.Time_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_Time;

   -------------------
   -- Validate_GDay --
   -------------------

   function Validate_GDay
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : GDay_T;
      Error : Symbol;
   begin
      Validate_GDay_Facets
        (Symbols, Ch,
         Descr.GDay_Min_Inclusive, Descr.GDay_Min_Exclusive,
         Descr.GDay_Max_Inclusive, Descr.GDay_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_GDay;

   -------------------------
   -- Validate_GMonth_Day --
   -------------------------

   function Validate_GMonth_Day
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : GMonth_Day_T;
      Error : Symbol;
   begin
      Validate_GMonth_Day_Facets
        (Symbols, Ch,
         Descr.GMonthDay_Min_Inclusive, Descr.GMonthDay_Min_Exclusive,
         Descr.GMonthDay_Max_Inclusive, Descr.GMonthDay_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_GMonth_Day;

   ---------------------
   -- Validate_GMonth --
   ---------------------

   function Validate_GMonth
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : GMonth_T;
      Error : Symbol;
   begin
      Validate_GMonth_Facets
        (Symbols, Ch,
         Descr.GMonth_Min_Inclusive, Descr.GMonth_Min_Exclusive,
         Descr.GMonth_Max_Inclusive, Descr.GMonth_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_GMonth;

   --------------------
   -- Validate_GYear --
   --------------------

   function Validate_GYear
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : GYear_T;
      Error : Symbol;
   begin
      Validate_GYear_Facets
        (Symbols, Ch,
         Descr.GYear_Min_Inclusive, Descr.GYear_Min_Exclusive,
         Descr.GYear_Max_Inclusive, Descr.GYear_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_GYear;

   --------------------------
   -- Validate_GYear_Month --
   --------------------------

   function Validate_GYear_Month
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Val   : GYear_Month_T;
      Error : Symbol;
   begin
      Validate_GYear_Month_Facets
        (Symbols, Ch,
         Descr.GYearMonth_Min_Inclusive, Descr.GYearMonth_Min_Exclusive,
         Descr.GYearMonth_Max_Inclusive, Descr.GYearMonth_Max_Exclusive,
         Error, Val);
      return Error;
   end Validate_GYear_Month;

   ----------------------
   -- Validate_Decimal --
   ----------------------

   function Validate_Decimal
     (Descr         : Simple_Type_Descr;
      Symbols       : Sax.Utils.Symbol_Table;
      Ch            : Unicode.CES.Byte_Sequence) return Symbol
   is
      Error : Symbol;
      Val   : Arbitrary_Precision_Number;
   begin
      Validate_Decimal_Facets
        (Symbols, Ch,
         Descr.Decimal_Min_Inclusive, Descr.Decimal_Min_Exclusive,
         Descr.Decimal_Max_Inclusive, Descr.Decimal_Max_Exclusive,
        Error, Val);
      if Error /= No_Symbol then
         return Error;
      end if;

      return Check_Digits
        (Symbols         => Symbols,
         Num             => Val,
         Fraction_Digits => Descr.Fraction_Digits,
         Total_Digits    => Descr.Total_Digits);
   end Validate_Decimal;

   ------------------
   -- Equal_String --
   ------------------

   function Equal_String
     (Descr : Simple_Type_Descr;
      Symbols : Symbol_Table;
      Ch1   : Symbol;
      Ch2   : Byte_Sequence) return Boolean
   is
      pragma Unreferenced (Descr, Symbols);
   begin
      return Get (Ch1).all = Ch2;
   end Equal_String;

   --------------------
   -- Convert_Regexp --
   --------------------

   function Convert_Regexp
     (Regexp : Unicode.CES.Byte_Sequence) return String
   is
      Result : Unbounded_String;
      Tmp    : Unbounded_String;
      Pos    : Integer := Regexp'First;
      C      : Character;

      function Next_Char return Character;
      --  Read the next char from the regexp, and check it is ASCII

      function Next_Char return Character is
         Char   : Unicode_Char;
      begin
         Encoding.Read (Regexp, Pos, Char);

         if Char > 127 then
            Raise_Exception
              (XML_Not_Implemented'Identity,
               "Unicode regexps are not supported");
         end if;

         return Character'Val (Integer (Char));
      end Next_Char;

   begin
      while Pos <= Regexp'Last loop
         C := Next_Char;

         if C = '[' then
            Append (Result, C);
            Tmp := Null_Unbounded_String;

            while Pos <= Regexp'Last loop
               C := Next_Char;

               if C = ']' then
                  Append (Tmp, C);
                  exit;

               elsif C = '\' and then Pos <= Regexp'Last then
                  C := Next_Char;

                  case C is
                     when 'i' =>
                        --  rule [99] in XMLSchema specifications
                        Append (Tmp, "A-Za-z:_");

                     when 'c' =>
                        Append (Tmp, "a-z:A-Z0-9._-");

                     when 'w' =>
                        Append (Tmp, "a-zA-Z0-9`");

                     when 'I' | 'C' =>
                        Raise_Exception
                          (XML_Not_Implemented'Identity,
                           "Unsupported regexp construct: \" & C);

                     when 'P' | 'p' =>
                        if Pos <= Regexp'Last
                          and then Regexp (Pos) = '{'
                        then
                           Raise_Exception
                             (XML_Not_Implemented'Identity,
                              "Unsupported regexp construct: \P{...}");
                        else
                           Append (Tmp, '\' & C);
                        end if;

                     when others =>
                        Append (Tmp, '\' & C);
                  end case;

               else
                  if C = '-'
                    and then Pos <= Regexp'Last
                    and then Regexp (Pos) = '['
                  then
                     Raise_Exception
                       (XML_Not_Implemented'Identity,
                        "Unsupported regexp construct: [...-[...]]");
                  end if;

                  Append (Tmp, C);
               end if;
            end loop;

            Append (Result, Tmp);

         --  ??? Some tests in the old w3c testsuite seem to imply that
         --  \c and \i are valid even outside character classes. Not sure about
         --  this though

         elsif C = '\' and then Pos <= Regexp'Last then
            C := Next_Char;

            case C is
               when 'i' =>
                  --  rule [99] in XMLSchema specifications
                  Append (Result, "[A-Za-z:_]");

               when 'c' =>
                  Append (Result, "[a-z:A-Z0-9._-]");

               when 'w' =>
                  Append (Result, "[a-zA-Z0-9`]");

               when 'I' | 'C' =>
                  Raise_Exception
                    (XML_Not_Implemented'Identity,
                     "Unsupported regexp construct: \" & C);

               when 'P' | 'p' =>
                  if Pos <= Regexp'Last
                    and then Regexp (Pos) = '{'
                  then
                     Raise_Exception
                       (XML_Not_Implemented'Identity,
                        "Unsupported regexp construct: \P{...}");
                  else
                     Append (Result, '\' & C);
                  end if;

               when others =>
                  Append (Result, '\' & C);
            end case;

         else
            Append (Result, C);
         end if;
      end loop;

      return Anchor (To_String (Result));
   end Convert_Regexp;

   ------------------------
   -- Missing_End_Anchor --
   ------------------------

   function Missing_End_Anchor (Str : String) return Boolean is
   begin
      --  Do not add '$' if Str ends with a single \, since it is
      --  invalid anyway
      return Str'Length = 0
        or else
          (Str (Str'Last) /= '$'
           and then (Str (Str'Last) /= '\'
                     or else (Str'Length /= 1
                              and then Str (Str'Last - 1) = '\')));
   end Missing_End_Anchor;

   --------------------------
   -- Missing_Start_Anchor --
   --------------------------

   function Missing_Start_Anchor (Str : String) return Boolean is
   begin
      --  Do not add '^' if we start with an operator, since Str is invalid
      return Str'Length = 0
        or else not (Str (Str'First) = '^'
                     or else Str (Str'First) = '*'
                     or else Str (Str'First) = '+'
                     or else Str (Str'First) = '?');
   end Missing_Start_Anchor;

   ------------
   -- Anchor --
   ------------

   function Anchor (Str : String) return String is
      Start : constant Boolean := Missing_Start_Anchor (Str);
      Last  : constant Boolean := Missing_End_Anchor (Str);
   begin
      if Start and Last then
         return "^(" & Str & ")$";
      elsif Start then
         return "^" & Str;
      elsif Last then
         return Str & "$";
      else
         return Str;
      end if;
   end Anchor;

   ---------------
   -- Add_Facet --
   ---------------

   procedure Add_Facet
     (Facets       : in out All_Facets;
      Symbols      : Sax.Utils.Symbol_Table;
      Enumerations : in out Enumeration_Tables.Instance;
      Facet_Name   : Sax.Symbols.Symbol;
      Value        : Sax.Symbols.Symbol;
      Loc          : Sax.Locators.Location)
   is
      Val : constant Symbol := Find
        (Symbols, Trim (Get (Value).all, Ada.Strings.Both));
   begin
      if Get (Facet_Name).all = "whiteSpace" then
         Facets (Facet_Whitespace) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "enumeration" then
         Append (Enumerations, (Value => Val,
                                Next  => Facets (Facet_Enumeration).Enum));
         Facets (Facet_Enumeration) := (No_Symbol, Last (Enumerations), Loc);
      elsif Get (Facet_Name).all = "pattern" then
         Facets (Facet_Pattern) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "minInclusive" then
         Facets (Facet_Min_Inclusive) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "maxInclusive" then
         Facets (Facet_Max_Inclusive) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "minExclusive" then
         Facets (Facet_Min_Exclusive) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "maxExclusive" then
         Facets (Facet_Max_Exclusive) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "length" then
         Facets (Facet_Length) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "minLength" then
         Facets (Facet_Min_Length) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "maxLength" then
         Facets (Facet_Max_Length) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "totalDigits" then
         Facets (Facet_Total_Digits) := (Val, No_Enumeration_Index, Loc);
      elsif Get (Facet_Name).all = "fractionDigits" then
         Facets (Facet_Fraction_Digits) := (Val, No_Enumeration_Index, Loc);
      else
         pragma Assert (False, "Invalid facet: " & Get (Facet_Name).all);
         null;
      end if;
   end Add_Facet;

   ---------------------------------
   -- Override_Single_Range_Facet --
   ---------------------------------

   procedure Override_Single_Range_Facet
     (Symbols       : Sax.Utils.Symbol_Table;
      Facet         : Facet_Value;
      Val           : in out T;
      Error         : in out Symbol;
      Error_Loc     : in out Location) is
   begin
      if Error = No_Symbol and then Facet /= No_Facet_Value then
         Value
           (Symbols,
            Ch    => Get (Facet.Value).all,
            Val   => Val,
            Error => Error);
         if Error /= No_Symbol then
            Error_Loc := Facet.Loc;
         end if;
      end if;
   end Override_Single_Range_Facet;

   ---------------------------
   -- Override_Range_Facets --
   ---------------------------

   procedure Override_Range_Facets
     (Symbols       : Sax.Utils.Symbol_Table;
      Facets        : All_Facets;
      Min_Inclusive : in out T;
      Min_Exclusive : in out T;
      Max_Inclusive : in out T;
      Max_Exclusive : in out T;
      Error         : out Symbol;
      Error_Loc     : out Location)
   is
      procedure Do_Override is new Override_Single_Range_Facet (T, Value);
   begin
      Do_Override (Symbols, Facets (Facet_Max_Inclusive),
                   Max_Inclusive, Error, Error_Loc);
      Do_Override (Symbols, Facets (Facet_Max_Exclusive),
                   Max_Exclusive, Error, Error_Loc);
      Do_Override (Symbols, Facets (Facet_Min_Inclusive),
                   Min_Inclusive, Error, Error_Loc);
      Do_Override (Symbols, Facets (Facet_Min_Exclusive),
                   Min_Exclusive, Error, Error_Loc);
   end Override_Range_Facets;

   procedure Override_Decimal_Facets
     is new Override_Range_Facets (Arbitrary_Precision_Number);
   procedure Override_Float_Facets is new Override_Range_Facets (XML_Float);
   procedure Override_Duration_Facets
     is new Override_Range_Facets (Duration_T);
   procedure Override_Date_Time_Facets
     is new Override_Range_Facets (Date_Time_T);
   procedure Override_Date_Facets is new Override_Range_Facets (Date_T);
   procedure Override_Time_Facets is new Override_Range_Facets (Time_T);
   procedure Override_GDay_Facets is new Override_Range_Facets (GDay_T);
   procedure Override_GMonth_Day_Facets
     is new Override_Range_Facets (GMonth_Day_T);
   procedure Override_GMonth_Facets is new Override_Range_Facets (GMonth_T);
   procedure Override_GYear_Facets is new Override_Range_Facets (GYear_T);
   procedure Override_GYear_Month_Facets
     is new Override_Range_Facets (GYear_Month_T);

   --------------
   -- Override --
   --------------

   procedure Override
     (Simple     : in out Simple_Type_Descr;
      Facets     : All_Facets;
      Symbols    : Sax.Utils.Symbol_Table;
      Error      : out Sax.Symbols.Symbol;
      Error_Loc  : out Sax.Locators.Location)
   is
      Val : Symbol;
   begin
      pragma Assert (Simple.Kind /= Facets_Union,
                     "can't merge facets for a <union>");

      if Facets (Facet_Whitespace) /= No_Facet_Value then
         Val := Facets (Facet_Whitespace).Value;
         if Get (Val).all = "preserve" then
            Simple.Whitespace := Preserve;
         elsif Get (Val).all = "replace" then
            Simple.Whitespace := Replace;
         elsif Get (Val).all = "collapse" then
            Simple.Whitespace := Collapse;
         else
            Error_Loc := Facets (Facet_Whitespace).Loc;
            Error := Find (Symbols, "Invalid value for whiteSpace facet: "
                           & Get (Val).all);
            return;
         end if;
      end if;

      if Facets (Facet_Pattern) /= No_Facet_Value then
         Val := Facets (Facet_Pattern).Value;

         if Simple.Pattern_String = No_Symbol then
            Simple.Pattern_String := Val;
         else
            Simple.Pattern_String := Find
              (Symbols,
               '(' & Get (Simple.Pattern_String).all
               & ")|(" & Get (Val).all & ')');
         end if;

         Unchecked_Free (Simple.Pattern);

         declare
            Convert : constant String :=
              Convert_Regexp (Get (Simple.Pattern_String).all);
         begin
            if Debug then
               Debug_Output ("Compiling regexp as " & Convert);
            end if;
            Simple.Pattern := new Pattern_Matcher'(Compile (Convert));
         exception
            when  GNAT.Regpat.Expression_Error =>
               Error_Loc := Facets (Facet_Pattern).Loc;
               Error := Find
                 (Symbols,
                  "Invalid regular expression "
                  & Get (Simple.Pattern_String).all
                  & " (converted to " & Convert & ")");
         end;
      end if;

      if Facets (Facet_Enumeration) /= No_Facet_Value then
         Simple.Enumeration := Facets (Facet_Enumeration).Enum;
      end if;

      Error := No_Symbol;

      case Simple.Kind is
         when Facets_Union =>
            null;

         when Facets_String .. Facets_HexBinary =>
            if Facets (Facet_Length) /= No_Facet_Value then
               Simple.String_Length := Natural'Value
                 (Get (Facets (Facet_Length).Value).all);
            end if;

            if Facets (Facet_Min_Length) /= No_Facet_Value then
               Simple.String_Min_Length := Natural'Value
                 (Get (Facets (Facet_Min_Length).Value).all);
            end if;

            if Facets (Facet_Max_Length) /= No_Facet_Value then
               Simple.String_Max_Length := Natural'Value
                 (Get (Facets (Facet_Max_Length).Value).all);
            end if;

         when Facets_Boolean =>
            null;

         when Facets_Float | Facets_Double  =>
            Override_Float_Facets
              (Symbols, Facets,
               Simple.Float_Min_Inclusive, Simple.Float_Min_Exclusive,
               Simple.Float_Max_Inclusive, Simple.Float_Max_Exclusive,
               Error, Error_Loc);

         when Facets_Decimal =>
            Override_Decimal_Facets
              (Symbols, Facets,
               Simple.Decimal_Min_Inclusive, Simple.Decimal_Min_Exclusive,
               Simple.Decimal_Max_Inclusive, Simple.Decimal_Max_Exclusive,
               Error, Error_Loc);

            if Error = No_Symbol then
               if Facets (Facet_Total_Digits) /= No_Facet_Value then
                  Simple.Total_Digits := Positive'Value
                    (Get (Facets (Facet_Total_Digits).Value).all);
               end if;

               if Facets (Facet_Fraction_Digits) /= No_Facet_Value then
                  Simple.Fraction_Digits := Natural'Value
                    (Get (Facets (Facet_Fraction_Digits).Value).all);
               end if;

               if Simple.Fraction_Digits > Simple.Total_Digits then
                  Error_Loc := Facets (Facet_Fraction_Digits).Loc;
                  Error := Find
                    (Symbols,
                     "fractionDigits cannot be greater than totalDigits");
               end if;
            end if;

         when Facets_Time =>
            Override_Time_Facets
              (Symbols, Facets,
               Simple.Time_Min_Inclusive, Simple.Time_Min_Exclusive,
               Simple.Time_Max_Inclusive, Simple.Time_Max_Exclusive,
               Error, Error_Loc);

         when Facets_DateTime =>
            Override_Date_Time_Facets
              (Symbols, Facets,
               Simple.DateTime_Min_Inclusive, Simple.DateTime_Min_Exclusive,
               Simple.DateTime_Max_Inclusive, Simple.DateTime_Max_Exclusive,
               Error, Error_Loc);

         when Facets_GDay =>
            Override_GDay_Facets
              (Symbols, Facets,
               Simple.GDay_Min_Inclusive, Simple.GDay_Min_Exclusive,
               Simple.GDay_Max_Inclusive, Simple.GDay_Max_Exclusive,
               Error, Error_Loc);

         when Facets_GMonthDay =>
            Override_GMonth_Day_Facets
              (Symbols, Facets,
               Simple.GMonthDay_Min_Inclusive, Simple.GMonthDay_Min_Exclusive,
               Simple.GMonthDay_Max_Inclusive, Simple.GMonthDay_Max_Exclusive,
               Error, Error_Loc);

         when Facets_GMonth =>
            Override_GMonth_Facets
              (Symbols, Facets,
               Simple.GMonth_Min_Inclusive, Simple.GMonth_Min_Exclusive,
               Simple.GMonth_Max_Inclusive, Simple.GMonth_Max_Exclusive,
               Error, Error_Loc);

         when Facets_GYearMonth =>
            Override_GYear_Month_Facets
              (Symbols, Facets,
               Simple.GYearMonth_Min_Inclusive,
               Simple.GYearMonth_Min_Exclusive,
               Simple.GYearMonth_Max_Inclusive,
               Simple.GYearMonth_Max_Exclusive,
               Error, Error_Loc);

         when Facets_GYear =>
            Override_GYear_Facets
              (Symbols, Facets,
               Simple.GYear_Min_Inclusive, Simple.GYear_Min_Exclusive,
               Simple.GYear_Max_Inclusive, Simple.GYear_Max_Exclusive,
               Error, Error_Loc);

         when Facets_Date =>
            Override_Date_Facets
              (Symbols, Facets,
               Simple.Date_Min_Inclusive, Simple.Date_Min_Exclusive,
               Simple.Date_Max_Inclusive, Simple.Date_Max_Exclusive,
               Error, Error_Loc);

         when Facets_Duration =>
            Override_Duration_Facets
              (Symbols, Facets,
               Simple.Duration_Min_Inclusive, Simple.Duration_Min_Exclusive,
               Simple.Duration_Max_Inclusive, Simple.Duration_Max_Exclusive,
               Error, Error_Loc);
      end case;

      --  ??? Should detect unused facets and report errors
   end Override;

end Schema.Simple_Types;
